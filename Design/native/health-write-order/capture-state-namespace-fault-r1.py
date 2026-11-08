"""Bounded synthetic root-file fault with an append-only durable phase journal.

No producer runs on import. The caller must verify the dedicated simulator,
fixture, source/control/run and protected current/prior/default/provider facts.
RENAME_EXCL=4 and renameatx_np signature checked in the installed macOS SDK's
usr/include/sys/stdio.h. No overwrite fallback is permitted.
"""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import stat
import time
import uuid

FIELDS = ('st_dev', 'st_ino', 'st_mode', 'st_nlink', 'st_size', 'st_mtime_ns')
sha = lambda value: hashlib.sha256(value).hexdigest()


def identity(path):
    facts = Path(path).lstat()
    assert not stat.S_ISLNK(facts.st_mode), str(path)
    return {key: getattr(facts, key) for key in FIELDS}


def directory_identity(path):
    facts = identity(path)
    assert stat.S_ISDIR(facts['st_mode'])
    return {key: facts[key] for key in ('st_dev', 'st_ino', 'st_mode')}


def tree(path):
    directory_identity(path)
    files, directories = {}, []
    total = 0
    for parent, dirs, names in os.walk(path, followlinks=False):
        for name in dirs:
            child = Path(parent) / name
            directory_identity(child)
            directories.append(str(child.relative_to(path)))
        for name in names:
            child = Path(parent) / name
            facts = identity(child)
            assert stat.S_ISREG(facts['st_mode']) and facts['st_size'] <= 256 * 1024
            data = child.read_bytes()
            total += len(data)
            assert total <= 2 * 1024 * 1024
            files[str(child.relative_to(path))] = {'identity': facts, 'bytes': len(data), 'sha256': sha(data)}
    return {'files': files, 'directories': sorted(directories)}


class SyntheticRootFileFault:
    def __init__(self, root, *, run_id, nonce, protected):
        self.root = Path(root)
        assert self.root.is_absolute() and self.root.name == 'LumenData'
        self.run_id, self.nonce = str(uuid.UUID(run_id)), str(uuid.UUID(nonce))
        self.parent = self.root.parent
        self.parent_identity = directory_identity(self.parent)
        self.root_identity = directory_identity(self.root)
        self.original = tree(self.root)
        self.protected = protected
        assert protected['current'] == self.original
        assert protected['prior'] == tree(self.root.with_suffix('.previous'))
        # Refuse even this artificial fault unless it is the known small fixture.
        water = json.loads((self.root / 'water.json').read_bytes())
        goals = json.loads((self.root / 'goals.json').read_bytes())
        assert len(water) == 1 and water[0]['id'] == 'synthetic-review-water' and water[0]['ml'] == 137
        assert [goals[key] for key in ('stepGoal', 'weightKg', 'heightCm', 'age')] == [6543, 88.5, 181, 42]
        assert not self.original['directories'] and len(self.original['files']) == 10
        self.moved = self.parent / ('LumenData.capture-fault-' + self.nonce)
        self.journal = self.parent / ('Lumen-capture-fault-journal-' + self.nonce + '.jsonl')
        assert not os.path.lexists(self.moved) and not os.path.lexists(self.journal)
        self.sentinel = ('Lumen synthetic capture fault ' + self.run_id + ' ' + self.nonce + '\n').encode()
        self.sentinel_identity = None
        self.parent_fd = os.open(self.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        self.journal_fd = None
        self.closed = False
        try:
            facts = os.fstat(self.parent_fd)
            assert all(getattr(facts, key) == value for key, value in self.parent_identity.items())
            self.journal_fd = os.open(self.journal.name,
                os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=self.parent_fd)
            self.record('prepared', protected=protected, originalRoot=self.root_identity,
                        originalTree=self.original, movedName=self.moved.name,
                        sentinelBytes=len(self.sentinel), sentinelSHA256=sha(self.sentinel))
        except BaseException:
            self.close()
            raise

    def recovery_descriptor(self):
        """Caller persists this exact known-run descriptor before installing the fault."""
        facts = os.fstat(self.journal_fd)
        return {'runID': self.run_id, 'nonce': self.nonce, 'root': str(self.root),
                'parentIdentity': self.parent_identity, 'rootIdentity': self.root_identity,
                'protected': self.protected,
                'journalIdentity': {key: getattr(facts, key) for key in ('st_dev', 'st_ino', 'st_mode', 'st_nlink')}}

    @classmethod
    def resume(cls, descriptor):
        """Reconcile only a separately retained known-run descriptor, never an unknown journal.

        Partial/unparseable journals or an unrecorded partial sentinel fail closed.
        This API is not evidence that process-crash recovery was executed.
        """
        value = cls.__new__(cls)
        value.root = Path(descriptor['root'])
        assert value.root.is_absolute() and value.root.name == 'LumenData'
        value.parent = value.root.parent
        value.run_id = str(uuid.UUID(descriptor['runID']))
        value.nonce = str(uuid.UUID(descriptor['nonce']))
        value.parent_identity = descriptor['parentIdentity']
        assert directory_identity(value.parent) == value.parent_identity
        value.root_identity = descriptor['rootIdentity']
        value.protected = descriptor['protected']
        value.original = value.protected['current']
        value.moved = value.parent / ('LumenData.capture-fault-' + value.nonce)
        value.journal = value.parent / ('Lumen-capture-fault-journal-' + value.nonce + '.jsonl')
        value.sentinel = ('Lumen synthetic capture fault ' + value.run_id + ' ' + value.nonce + '\n').encode()
        value.sentinel_identity = None
        facts = identity(value.journal)
        assert stat.S_ISREG(facts['st_mode']) and facts['st_size'] <= 2 * 1024 * 1024
        assert all(facts[key] == expected for key, expected in descriptor['journalIdentity'].items())
        data = value.journal.read_bytes()
        assert data.endswith(b'\n')
        rows = [json.loads(line) for line in data.splitlines()]
        assert rows and rows[0]['phase'] == 'prepared'
        assert rows[0]['protected'] == value.protected and rows[0]['originalRoot'] == value.root_identity
        assert rows[0]['originalTree'] == value.original and rows[0]['movedName'] == value.moved.name
        assert rows[0]['sentinelSHA256'] == sha(value.sentinel)
        assert all(row['runID'] == value.run_id and row['nonce'] == value.nonce and
                   row['parentIdentity'] == value.parent_identity for row in rows)
        for row in rows:
            if row.get('sentinelIdentity') is not None:
                if value.sentinel_identity is not None:
                    assert value.sentinel_identity == row['sentinelIdentity']
                value.sentinel_identity = row['sentinelIdentity']
        value.parent_fd = os.open(value.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        value.journal_fd = None
        value.closed = False
        try:
            value.check_parent()
            value.journal_fd = os.open(value.journal.name, os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW,
                                       dir_fd=value.parent_fd)
            opened = os.fstat(value.journal_fd)
            assert all(getattr(opened, key) == expected for key, expected in descriptor['journalIdentity'].items())
            value.record('resumed-known-descriptor')
            return value
        except BaseException:
            value.close()
            raise

    def check_parent(self):
        assert not self.closed and directory_identity(self.parent) == self.parent_identity
        facts = os.fstat(self.parent_fd)
        assert all(getattr(facts, key) == value for key, value in self.parent_identity.items())

    def record(self, phase, **facts):
        self.check_parent()
        row = {'phase': phase, 'runID': self.run_id, 'nonce': self.nonce,
               'at': time.time(), 'parentIdentity': self.parent_identity, **facts}
        data = (json.dumps(row, sort_keys=True, separators=(',', ':')) + '\n').encode()
        view = memoryview(data)
        while view:
            count = os.write(self.journal_fd, view)
            assert count > 0
            view = view[count:]
        os.fsync(self.journal_fd)
        os.fsync(self.parent_fd)

    def rename_exclusive(self, source, destination):
        self.check_parent()
        assert Path(source).name == source and Path(destination).name == destination
        library = ctypes.CDLL(None, use_errno=True)
        call = library.renameatx_np
        call.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        call.restype = ctypes.c_int
        if call(self.parent_fd, os.fsencode(source), self.parent_fd, os.fsencode(destination), 4) != 0:
            code = ctypes.get_errno()
            raise OSError(code, os.strerror(code), destination)
        os.fsync(self.parent_fd)

    def moved_exact(self):
        self.check_parent()
        assert directory_identity(self.moved) == self.root_identity and tree(self.moved) == self.original

    def install(self):
        self.check_parent()
        assert directory_identity(self.root) == self.root_identity and tree(self.root) == self.original
        self.record('rename-intended')
        try:
            self.rename_exclusive(self.root.name, self.moved.name)
            self.moved_exact()
            self.record('root-moved', movedRoot=self.root_identity, movedTree=tree(self.moved))
            assert not os.path.lexists(self.root)
            self.record('sentinel-create-intended')
            fd = os.open(self.root.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=self.parent_fd)
            try:
                os.fchmod(fd, 0o600)
                view = memoryview(self.sentinel)
                while view:
                    count = os.write(fd, view)
                    assert count > 0
                    view = view[count:]
                os.fsync(fd)
                facts = os.fstat(fd)
                self.sentinel_identity = {key: getattr(facts, key) for key in FIELDS}
            finally:
                os.close(fd)
            self.assert_sentinel()
            self.record('sentinel-created', sentinelIdentity=self.sentinel_identity)
        except BaseException as error:
            self.record('install-failed', errorType=type(error).__name__, error=repr(error),
                        sentinelIdentity=self.sentinel_identity)
            raise

    def assert_sentinel(self):
        self.check_parent()
        assert self.sentinel_identity is not None
        assert identity(self.root) == self.sentinel_identity
        assert stat.S_ISREG(self.sentinel_identity['st_mode']) and self.root.read_bytes() == self.sentinel
        self.moved_exact()

    def restore(self):
        """Reconcile actual namespace, including rename-before-journal completion.

        A foreign/changed original or moved path is retained. This function never
        treats a failed finally block as successful restoration.
        """
        try:
            self.check_parent()
            root_exists, moved_exists = os.path.lexists(self.root), os.path.lexists(self.moved)
            if root_exists and not moved_exists:
                assert directory_identity(self.root) == self.root_identity and tree(self.root) == self.original
                self.record('restored-already-exact')
                return
            self.moved_exact()
            if root_exists:
                self.assert_sentinel()
                self.record('sentinel-remove-intended', sentinelIdentity=self.sentinel_identity)
                # Only the already verified known sentinel in this bounded quiet fixture.
                os.unlink(self.root.name, dir_fd=self.parent_fd)
                os.fsync(self.parent_fd)
                self.record('sentinel-removed')
            else:
                self.record('root-absent-reconciliation')
            assert not os.path.lexists(self.root)
            self.record('restore-rename-intended')
            self.rename_exclusive(self.moved.name, self.root.name)
            assert directory_identity(self.root) == self.root_identity and tree(self.root) == self.original
            assert not os.path.lexists(self.moved)
            self.record('restored', restoredRoot=self.root_identity, restoredTree=tree(self.root))
        except BaseException as error:
            self.record('restoration-failed-owner-action-required', errorType=type(error).__name__, error=repr(error),
                        originalExists=os.path.lexists(self.root), movedExists=os.path.lexists(self.moved))
            raise

    def close(self):
        if not self.closed:
            if self.journal_fd is not None:
                os.close(self.journal_fd)
            os.close(self.parent_fd)
            self.closed = True
