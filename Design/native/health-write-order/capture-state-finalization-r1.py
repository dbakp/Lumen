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
