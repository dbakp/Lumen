"""Finite failure finalization for the dedicated synthetic capture test only.
No simulator mutation or producer on import. Callers retain actual observations.
"""
import json
import hashlib
import os
from pathlib import Path
import signal
import subprocess
import time


def durable_json(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + '.terminal-tmp')
    data = (json.dumps(value, indent=2) + '\n').encode()
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        parent = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(parent)
        finally:
            os.close(parent)
    finally:
        # Preserve the temporary file on any incomplete persistence; no deletion.
        pass


def finish_native(process, state, persist, *, natural_waits=6, natural_seconds=30,
                  interrupt_waits=3, interrupt_seconds=10):
    """First permit native failure attachments/summary to complete naturally."""
    if process is None:
        return None
    state['nativeFinalization'] = {'naturalWaitSeconds': natural_waits * natural_seconds,
        'interruptFallbackSeconds': interrupt_waits * interrupt_seconds, 'samples': []}
    facts = state['nativeFinalization']
    persist()
    for attempt in range(natural_waits):
        if process.poll() is not None:
            break
        try:
            process.wait(timeout=natural_seconds)
        except subprocess.TimeoutExpired:
            pass
        facts['samples'].append({'attempt': attempt + 1, 'at': time.time(), 'exit': process.poll()})
        persist()
    if process.poll() is None:
        process.send_signal(signal.SIGINT)
        facts['interruptSentAt'] = time.time()
        persist()
        for attempt in range(interrupt_waits):
            try:
                process.wait(timeout=interrupt_seconds)
                break
            except subprocess.TimeoutExpired:
                facts['interruptWaits'] = attempt + 1
                persist()
    if process.poll() is None:
        process.kill()
        facts['forcedTerminationAt'] = time.time()
        persist()
        process.wait(timeout=10)
    facts['exit'] = process.returncode
    facts['finishedAt'] = time.time()
    persist()
    return process.returncode


def terminate_known_app(device, executable, pid, state, persist):
    """Restore only after native producer ended and this actual app PID is absent.

    Detached capture work lives inside the app process. Two process-table absence
    observations bound this check; this is not universal process-relaunch proof.
    No host process kill, workspace deletion or unrelated app termination.
    """
    assert device == 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
    executable = str(executable)
    assert Path(executable).name == 'Lumen' and '/Lumen.app/Lumen' in executable
    assert isinstance(pid, int) and pid > 0
    facts = {'device': device, 'executable': executable, 'knownPID': pid, 'samples': []}
    state['failureAppTermination'] = facts
    persist()

    def scan():
        query = subprocess.run(['ps', '-axo', 'pid=,comm='], capture_output=True, text=True, timeout=10)
        sample = {'at': time.time(), 'command': ['ps', '-axo', 'pid=,comm='],
                  'exit': query.returncode, 'stdoutBytes': len(query.stdout.encode()),
                  'stdoutSHA256': hashlib.sha256(query.stdout.encode()).hexdigest(), 'stderr': query.stderr}
        facts['samples'].append(sample)
        persist()
        assert query.returncode == 0, 'Process absence not established'
        rows = [line.strip().split(None, 1) for line in query.stdout.splitlines() if line.strip()]
        assert all(len(row) == 2 and row[0].isdigit() for row in rows)
        known = [row for row in rows if int(row[0]) == pid]
        assert not known or known[0][1] == executable, 'PID identity changed; retain fault for guarded recovery'
        matches = [row for row in rows if row[1] == executable or int(row[0]) == pid]
        sample['matchingProcesses'] = matches
        persist()
        return matches

    live = scan()
    if live:
        assert len(live) == 1 and int(live[0][0]) == pid, 'Unexpected extra app process; no restoration'
        operation = subprocess.run(['xcrun', 'simctl', 'terminate', device, 'com.dbakp.lumen'],
                                   capture_output=True, text=True, timeout=15)
        facts['terminate'] = {'exit': operation.returncode, 'stdout': operation.stdout, 'stderr': operation.stderr,
                              'at': time.time()}
        persist()
        # A failed terminate may mean the app exited between scans. Absence below
        # is mandatory regardless of command success; an exit code is not proof.
    deadline = time.monotonic() + 10
    consecutive = 0
    while consecutive < 2:
        matches = scan()
        consecutive = 0 if matches else consecutive + 1
        assert time.monotonic() < deadline, 'App/worker still present: preserve sentinel and moved root'
        if consecutive < 2:
            time.sleep(0.2)
    facts['knownAppAndInProcessWorkerAbsent'] = True
    facts['scope'] = 'Two bounded actual process-table observations; no universal relaunch/race/crash claim'
    persist()
    return facts


def record_outcome(path, outcome):
    """Never let an outcome write error skip independent failure salvage.

    A previous durable incomplete record is retained when replacement fails.
    Emergency path and stderr are fallbacks, not a disk-failure guarantee.
    """
    import traceback
    import sys
    try:
        durable_json(path, outcome)
        return None
    except BaseException:
        error = traceback.format_exc()
        outcome.setdefault('outcomePersistenceErrors', []).append(error)
        outcome.update(status='FAILED outcome persistence; no acceptance', driverExit=1)
        try:
            durable_json(Path(path).with_name(Path(path).name + '.emergency.json'), outcome)
        except BaseException:
            outcome['emergencyOutcomePersistenceError'] = traceback.format_exc()
            print(json.dumps(outcome), file=sys.stderr, flush=True)
        return error


def salvage_peers(base, raw, stem, prefix, outcome, outpath):
    """Independent bounded attempts after retainer import/call failure only.

    Full original generic retainer remains primary. This fallback preserves actual
    queries and available peers without declaring a completed helper/image count.
    """
    import gzip
    import traceback
    base, raw = Path(base), Path(raw)
    salvage = {'scope': 'Failure-only independent available-peer salvage; no acceptance', 'attempts': []}
    outcome['independentSalvage'] = salvage

    def attempt(label, operation):
        row = {'label': label, 'at': time.time()}
        salvage['attempts'].append(row)
        try:
            row['result'] = operation()
        except BaseException:
            row['error'] = traceback.format_exc()
        finally:
            record_outcome(outpath, outcome)

    def archive(path, label):
        assert path.is_file() and not path.is_symlink()
        data = path.read_bytes()
        target = base / (prefix + '-fallback-' + label + '.gz')
        target.write_bytes(gzip.compress(data, mtime=0))
        return {'file': target.name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}

    attempt('raw-log', lambda: archive(raw / (stem + '.log'), 'native-log'))
    result = raw / (stem + '.xcresult')
    for label, command in [
        ('summary', ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result)]),
        ('png-export', ['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(raw / (stem + 'PNG')), '--filter', '*.png']),
        ('json-export', ['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(raw / (stem + 'JSON')), '--filter', '*.json']),
    ]:
        def query(command=command, label=label):
            proc = subprocess.run(command, capture_output=True, timeout=60)
            facts = {'command': command, 'exit': proc.returncode}
            for stream, data in [('stdout', proc.stdout), ('stderr', proc.stderr)]:
                target = base / (prefix + '-fallback-' + label + '-' + stream + '.gz')
                target.write_bytes(gzip.compress(data, mtime=0))
                facts[stream] = {'file': target.name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
            return facts
        attempt(label, query)
    # Each export/manifest/peer remains an independent attempt after query failure.
    for extension in ['PNG', 'JSON']:
        directory = raw / (stem + extension)
        attempt(extension + '-manifest', lambda directory=directory, extension=extension: archive(directory / 'manifest.json', extension.lower() + '-manifest'))
        for path in sorted(directory.glob('*.png' if extension == 'PNG' else '*.json')):
            if path.name == 'manifest.json':
                continue
            attempt(extension + '-peer-' + path.name, lambda path=path, extension=extension: archive(path, extension.lower() + '-' + path.name))
    return salvage


def guarded_retain(loader, base, raw, stem, prefix, source, outcome, outpath):
    import traceback
    # A durable FAILED/incomplete record precedes loader and retention.
    outcome.update(status='INCOMPLETE retention pending; no acceptance', driverExit=1)
    persistence_error = record_outcome(outpath, outcome)
    retained = None
    error = persistence_error
    try:
        retainer = loader()
        retained = retainer.retain(base, raw, stem, prefix, source)
        outcome['retention'] = retained
        outcome['summary'] = retained.get('summary')
        if retained.get('errors'):
            error = json.dumps(retained['errors'])
            outcome.update(status='FAILED actual retention errors; no acceptance', driverExit=1)
    except BaseException:
        error = traceback.format_exc()
        outcome['retainerException'] = error
        outcome.update(status='FAILED retention; no acceptance', driverExit=1)
        # Still attempt later actual peers if the module import/call itself failed.
        try:
            salvage_peers(base, raw, stem, prefix, outcome, outpath)
        except BaseException:
            outcome['salvageException'] = traceback.format_exc()
    finally:
        last_error = record_outcome(outpath, outcome)
        error = error or last_error
    return retained, error
