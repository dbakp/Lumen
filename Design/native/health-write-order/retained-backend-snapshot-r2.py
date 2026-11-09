"""Bounded read-only persisted-state sampler. All errors/partial peers stay in result."""
import base64
import errno
import hashlib
import os
from pathlib import Path
import stat
import time
import traceback

FIELDS = ('st_dev','st_ino','st_mode','st_nlink','st_size','st_mtime_ns','st_ctime_ns')
MAX_ENTRIES = 512
MAX_FILE = 8 * 1024**2
MAX_TOTAL = 32 * 1024**2


def identity(value):
    return {key: getattr(value, key) for key in FIELDS}


def raw_fact(data):
    return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
            'base64': base64.b64encode(data).decode()}


def capture(roots):
    """Capture explicit named files/directories only; never traverse symlinks.

    Hardlinks are recorded, not rejected: actual transactions preserve by link.
    Caller must durably retain every attempt before interpreting or acknowledging.
    """
    assert type(roots) is dict and 0 < len(roots) <= 8 and all(type(k) is str for k in roots)
    result = {'status': 'SUPPORTED bounded persisted sample', 'startedAt': time.time(),
              'roots': {}, 'errors': [], 'entries': 0, 'totalReadBytes': 0}
    budget_exhausted = False

    def failure(label, stage, error):
        result['status'] = 'FAILED sample; no acknowledgement'
        result['errors'].append({'root': label, 'stage': stage, 'error': str(error)})

    def count():
        result['entries'] += 1
        if result['entries'] > MAX_ENTRIES:
            raise ValueError('Bounded entry budget exhausted')

    def file_at(parent, name, observed, record):
        nonlocal budget_exhausted
        record['identityObserved'] = identity(observed); count()
        if budget_exhausted: raise ValueError('Earlier byte budget exhausted; peer metadata retained')
        if not stat.S_ISREG(observed.st_mode) or observed.st_nlink < 1:
            raise ValueError('Unsafe nonregular file; not opened')
        if observed.st_size < 0 or observed.st_size > MAX_FILE:
            raise ValueError('Per-file byte bound exceeded; not opened')
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=parent)
        data = bytearray()
        try:
            before = os.fstat(fd); record['identityBefore'] = identity(before)
            if identity(before) != identity(observed) or not stat.S_ISREG(before.st_mode):
                raise ValueError('Opened file differs from observed regular entry')
            while len(data) <= MAX_FILE:
                chunk = os.read(fd, min(64*1024, MAX_FILE+1-len(data)))
                if not chunk: break
                data.extend(chunk); result['totalReadBytes'] += len(chunk)
                if result['totalReadBytes'] > MAX_TOTAL:
                    budget_exhausted = True; raise ValueError('Aggregate byte bound exceeded')
            record['raw'] = raw_fact(bytes(data))
            after = os.fstat(fd); record['identityAfter'] = identity(after)
            named = os.stat(name, dir_fd=parent, follow_symlinks=False); record['identityNamedAfter'] = identity(named)
            if len(data) != before.st_size or identity(before) != identity(after) or identity(after) != identity(named):
                raise ValueError('File bytes/identity/path changed during bounded read')
        finally:
            if 'raw' not in record: record['raw'] = raw_fact(bytes(data))
            os.close(fd)

    def bounded_names(fd, limit):
        names = []
        with os.scandir(fd) as entries:
            for entry in entries:
                names.append(entry.name)
                if len(names) > limit: break
        return {'names': sorted(names), 'overflow': len(names) > limit,
                'observedAtLeast': len(names), 'limit': limit}

    def directory_at(parent, name, observed, record, label, depth=0):
        record['identityObserved'] = identity(observed); count()
        if depth > 12: raise ValueError('Directory depth bound exceeded')
        if not stat.S_ISDIR(observed.st_mode): raise ValueError('Not a real directory')
        fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=parent)
        try:
            before = os.fstat(fd); record['identityBefore'] = identity(before)
            if identity(before) != identity(observed): raise ValueError('Opened directory identity mismatch')
            initial = bounded_names(fd, max(0, MAX_ENTRIES - result['entries']))
            names = initial['names']; record['inventoryBefore'] = initial
            record['namesBefore'] = names; record['children'] = {}
            if initial['overflow']: raise ValueError('Directory inventory exceeds remaining entry bound')
            for child in names:
                peer = {}; record['children'][child] = peer
                try:
                    if child in ('','.','..') or '/' in child or '\x00' in child: raise ValueError('Unsafe entry name')
                    facts = os.stat(child, dir_fd=fd, follow_symlinks=False); peer['kind'] = stat.S_IFMT(facts.st_mode)
                    if stat.S_ISDIR(facts.st_mode): directory_at(fd,child,facts,peer,label,depth+1)
                    else: file_at(fd,child,facts,peer)
                except BaseException as error:
                    peer['error'] = str(error); failure(label,'child '+child,error)
            final = bounded_names(fd, len(names)); record['inventoryAfter'] = final
            record['namesAfter'] = final['names']; after = os.fstat(fd)
            record['identityAfter'] = identity(after)
            named = os.stat(name, dir_fd=parent, follow_symlinks=False); record['identityNamedAfter'] = identity(named)
            if final['overflow'] or names != record['namesAfter'] or identity(before) != identity(after) or identity(after) != identity(named):
                raise ValueError('Directory inventory/identity/path changed during sample')
        finally: os.close(fd)

    def anchors(path):
        assert path.is_absolute() and '..' not in path.parts and path.name not in ('', '.', '..')
        opened = [os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)]
        links = []
        try:
            for part in path.parent.parts[1:]:
                parent = opened[-1]
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=parent)
                opened.append(child); links.append((parent,part,child))
            return opened, links
        except BaseException:
            for fd in reversed(opened): os.close(fd)
            raise

    for label, path in roots.items():
        record = {'path': str(path)}; result['roots'][label] = record
        try:
            path = Path(path)
            opened, links = anchors(path)  # Missing ancestors fail closed; only anchored leaf ENOENT is absence.
            try:
                parent = opened[-1]
                try: observed = os.stat(path.name, dir_fd=parent, follow_symlinks=False)
                except FileNotFoundError:
                    record['absent'] = True
                else:
                    record['absent'] = False; record['kind'] = stat.S_IFMT(observed.st_mode)
                    if stat.S_ISDIR(observed.st_mode): directory_at(parent,path.name,observed,record,label)
                    else: file_at(parent,path.name,observed,record)
                record['ancestorPathBindings'] = []
                for previous, name, fd in links:
                    descriptor = os.fstat(fd); named = os.stat(name,dir_fd=previous,follow_symlinks=False)
                    observed_link = {key:getattr(descriptor,key) for key in ('st_dev','st_ino','st_mode')}
                    named_link = {key:getattr(named,key) for key in ('st_dev','st_ino','st_mode')}
                    record['ancestorPathBindings'].append({'component':name,'descriptor':observed_link,'namedAfter':named_link})
                    if observed_link != named_link: raise ValueError('Ancestor pathname changed during sample')
            finally:
                for fd in reversed(opened): os.close(fd)
        except BaseException as error:
            record['error'] = str(error); failure(label,'root',error)
    result['finishedAt'] = time.time()
    return result


def files(sample, label):
    """Flatten retained regular rows without touching disk again."""
    root = sample['roots'][label]
    if root.get('absent'): return {}
    result = {}
    def visit(value, prefix=''):
        if 'children' in value:
            for name, child in value['children'].items(): visit(child,prefix+'/'+name if prefix else name)
        elif 'raw' in value:
            result[prefix] = value
    visit(root)
    return result
