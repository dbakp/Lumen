"""Actual isolated host-file operations only; no simulator/native/crash execution."""
import base64
import errno
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import time
import traceback
import uuid

sys.dont_write_bytecode = True
base = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('capture_fault_probe', base / 'capture-state-namespace-fault-r1.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
work = Path('/tmp/LumenCaptureNamespaceProbe218R1')
assert not work.exists(), 'Do not restart an existing probe set'
work.mkdir()
results = []


def fixture(name):
    parent = work / name
    root = parent / 'LumenData'
    root.mkdir(parents=True)
    values = {'water.json': [{'id': 'synthetic-review-water', 'ml': 137}],
        'goals.json': {'stepGoal': 6543, 'weightKg': 88.5, 'heightCm': 181, 'age': 42},
        **{name: [] for name in ['chat.json', 'conversations.json', 'conversation-selection.json',
            'sleep.json', 'today.json', 'profile.json', 'habits.json', 'health-write-intent.json']}}
    assert len(values) == 10
    for name, value in values.items():
        (root / name).write_text(json.dumps(value, sort_keys=True))
    shutil.copytree(root, root.with_suffix('.previous'))
    protected = {'current': m.tree(root), 'prior': m.tree(root.with_suffix('.previous')),
                 'scope': 'Known synthetic isolated fixture, not actual Lumen app data'}
    fault = m.SyntheticRootFileFault(root, run_id=str(uuid.uuid4()), nonce=str(uuid.uuid4()), protected=protected)
    return fault


def execute(name, operation):
    row = {'name': name, 'started': time.time()}
    results.append(row)
    try:
        operation(row)
        row['status'] = 'PASS'
    except BaseException:
        row['status'] = 'FAILED'
        row['error'] = traceback.format_exc()
        raise
    finally:
        row['finished'] = time.time()


def normal(row):
    f = fixture(row['name'])
    try:
        f.install(); f.assert_sentinel(); f.restore()
        assert m.tree(f.root) == f.original and not f.moved.exists()
        row['journal'] = str(f.journal)
    finally:
        f.close()


def rename_before_journal(row):
    f = fixture(row['name'])
    descriptor = f.recovery_descriptor()
    f.rename_exclusive(f.root.name, f.moved.name)
    f.close()
    resumed = m.SyntheticRootFileFault.resume(descriptor)
    try:
        resumed.restore()
        assert m.tree(resumed.root) == resumed.original and not resumed.moved.exists()
        row['journal'] = str(resumed.journal)
        row['limit'] = 'Second object resumes an actual rename; no process was killed'
    finally:
        resumed.close()


def foreign(row):
    f = fixture(row['name'])
    try:
        f.rename_exclusive(f.root.name, f.moved.name)
        f.root.write_bytes(b'Synthetic foreign-path canary; must not be moved or deleted.\n')
        before = f.root.read_bytes(), m.identity(f.root)
        try:
            f.restore()
        except AssertionError as error:
            row['expectedError'] = repr(error)
        else:
            raise AssertionError('Foreign original was accepted')
        assert (f.root.read_bytes(), m.identity(f.root)) == before
        assert m.tree(f.moved) == f.original
        row['foreignPreserved'] = True
    finally:
        f.close()


def collision(row):
    f = fixture(row['name'])
    try:
        f.install()
        original = f.rename_exclusive
        def collide(source, destination):
            assert source == f.moved.name and destination == f.root.name
            f.root.write_bytes(b'Synthetic exclusive-restore collision; preserve this path.\n')
            original(source, destination)
        f.rename_exclusive = collide
        try:
            f.restore()
        except OSError as error:
            assert error.errno == errno.EEXIST
            row['expectedError'] = repr(error)
        else:
            raise AssertionError('Exclusive destination collision accepted')
        assert f.root.read_bytes() == b'Synthetic exclusive-restore collision; preserve this path.\n'
        assert m.tree(f.moved) == f.original
        row['limit'] = 'Deterministically injected file creation, not an actual concurrent caller'
    finally:
        f.close()


def changed_sentinel(row):
    f = fixture(row['name'])
    try:
        f.install()
        with f.root.open('ab') as stream:
            stream.write(b'Synthetic modification')
        before = f.root.read_bytes(), m.identity(f.root)
        try:
            f.restore()
        except AssertionError as error:
            row['expectedError'] = repr(error)
        else:
            raise AssertionError('Changed sentinel was removed')
        assert (f.root.read_bytes(), m.identity(f.root)) == before and m.tree(f.moved) == f.original
    finally:
        f.close()


def resume_sentinel(row):
    f = fixture(row['name'])
    descriptor = f.recovery_descriptor()
    f.install(); f.close()
    resumed = m.SyntheticRootFileFault.resume(descriptor)
    try:
        resumed.restore()
        assert m.tree(resumed.root) == resumed.original and not resumed.moved.exists()
        row['journal'] = str(resumed.journal)
        row['limit'] = 'Same process/new object resume; no actual process-crash or power-loss proof'
    finally:
        resumed.close()


def no_install(row):
    f = fixture(row['name'])
    try:
        f.restore()
        assert m.tree(f.root) == f.original
    finally:
        f.close()


def truncated(row):
    f = fixture(row['name'])
    descriptor = f.recovery_descriptor()
    f.install(); f.close()
    f.journal.write_bytes(f.journal.read_bytes()[:-1])
    before = f.root.read_bytes(), m.identity(f.root), m.tree(f.moved)
    try:
        m.SyntheticRootFileFault.resume(descriptor)
    except AssertionError as error:
        row['expectedError'] = repr(error)
    else:
        raise AssertionError('Truncated journal accepted')
    assert (f.root.read_bytes(), m.identity(f.root), m.tree(f.moved)) == before


failure = None
try:
    for name, operation in [('normal-install-restore', normal), ('rename-before-journal-resume', rename_before_journal),
            ('foreign-original-blocked', foreign), ('exclusive-restore-collision-blocked', collision),
            ('changed-sentinel-blocked', changed_sentinel), ('recorded-sentinel-resume', resume_sentinel),
            ('no-install-exact-root', no_install), ('truncated-journal-blocked', truncated)]:
        execute(name, operation)
except BaseException:
    failure = traceback.format_exc()
finally:
    files = {}
    for parent, dirs, names in os.walk(work, followlinks=False):
        for name in dirs:
            assert not (Path(parent) / name).is_symlink()
        for name in names:
            path = Path(parent) / name
            assert not path.is_symlink() and path.is_file()
            data = path.read_bytes()
            files[str(path.relative_to(work))] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                                                'base64': base64.b64encode(data).decode()}
    archive = base / 'capture-state-namespace-isolated-probes-r1-artifacts.json.gz'
    archive.write_bytes(gzip.compress(json.dumps({'scope': 'Isolated synthetic host fixtures only', 'files': files},
        sort_keys=True).encode(), mtime=0))
    header = Path('/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/sys/stdio.h')
    output = {'status': 'PASS isolated host namespace probes' if failure is None else 'FAILED isolated host namespace probes',
        'passed': sum(row.get('status') == 'PASS' for row in results), 'expectedGuardErrors': sum('expectedError' in row for row in results),
        'results': results, 'failure': failure, 'workDirectory': str(work), 'artifacts': {'file': archive.name,
        'bytes': archive.stat().st_size, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'fullSyntheticFiles': len(files)},
        'module': {'file': 'capture-state-namespace-fault-r1.py', 'bytes': (base / 'capture-state-namespace-fault-r1.py').stat().st_size,
        'sha256': hashlib.sha256((base / 'capture-state-namespace-fault-r1.py').read_bytes()).hexdigest()},
        'SDKHeader': {'file': str(header), 'bytes': header.stat().st_size, 'sha256': hashlib.sha256(header.read_bytes()).hexdigest(),
            'exclusiveRenameFlag': 4}, 'scope': 'Actual isolated own-temp host operations;4expected failclosed controls. No simulator, app, native UI, actual concurrent race/process-crash/power-loss or global acceptance. Fixtures/archive retained through review/backup.',
        'checkedAt': time.time()}
    (base / 'capture-state-namespace-isolated-probes-r1.json').write_text(json.dumps(output, indent=2) + '\n')
    print(json.dumps({key: output[key] for key in ['status', 'passed', 'expectedGuardErrors', 'artifacts', 'failure']}), flush=True)
raise SystemExit(0 if failure is None else 1)
