"""Real isolated host children plus explicitly mocked process-table branches.
Never touches a simulator/app/root and never claims native failure acceptance.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch

BASE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('finalization_probe_subject', BASE / 'capture-state-finalization-r2.py')
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
report = {'scope': 'Isolated host subprocesses and explicitly mocked process queries; no simulator/native app/crash acceptance',
          'helperSHA256': hashlib.sha256((BASE / 'capture-state-finalization-r2.py').read_bytes()).hexdigest(), 'cases': []}
work = Path(tempfile.mkdtemp(prefix='LumenCaptureFinalization219R2-'))
report['work'] = str(work)


def child_case(name, program, *, interrupted=False, forced=False):
    folder = work / name
    folder.mkdir()
    script = folder / 'child.py'
    script.write_text(program)
    log = folder / 'child.log'
    state = {}
    def persist(): f.durable_json(folder / 'observations.json', state)
    with log.open('wb') as stream:
        process = subprocess.Popen([sys.executable, str(script)], stdout=stream, stderr=subprocess.STDOUT)
        until = time.monotonic() + 5
        while not (folder / 'ready').exists():
            assert process.poll() is None and time.monotonic() < until
            time.sleep(.01)
        code = f.finish_native(process, state, persist, natural_waits=2, natural_seconds=.1,
                               interrupt_waits=2, interrupt_seconds=.1)
    facts = state['nativeFinalization']
    assert ('interruptSentAt' in facts) is interrupted
    assert ('forcedTerminationAt' in facts) is forced
    assert process.poll() is not None
    if name == 'natural-failure-attachment':
        assert code == 1 and (folder / 'attachment.json').read_text() == '{"actual":"native child failure"}'
    if name == 'interrupt-fallback-attachment':
        assert code == 2 and (folder / 'attachment.json').read_text() == '{"actual":"interrupt callback"}'
    if forced: assert code < 0
    report['cases'].append({'case': name, 'status': 'PASS', 'actualChild': True, 'exit': code, 'facts': facts})


common = 'from pathlib import Path\nimport time,signal,sys\np=Path(__file__).parent\n'
child_case('natural-failure-attachment', common + '(p/"ready").write_text("ready")\ntime.sleep(.05)\n(p/"attachment.json").write_text(\'{"actual":"native child failure"}\')\nsys.exit(1)\n')
child_case('interrupt-fallback-attachment', common + 'def stop(*_):\n (p/"attachment.json").write_text(\'{"actual":"interrupt callback"}\');sys.exit(2)\nsignal.signal(signal.SIGINT,stop)\n(p/"ready").write_text("ready")\ntime.sleep(10)\n', interrupted=True)
child_case('forced-fallback', common + 'signal.signal(signal.SIGINT,signal.SIG_IGN)\n(p/"ready").write_text("ready")\ntime.sleep(10)\n', interrupted=True, forced=True)

executable = '/synthetic-only/Lumen.app/Lumen'
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
for name, tables, expected in [
    ('already-absent', ['', '', ''], True),
    ('failed-terminate-but-observed-absent', ['123 ' + executable, '', ''], True),
    ('failed-terminate-still-live', ['123 ' + executable] * 4, False),
    ('pid-reuse-refused', ['123 /unrelated/program'], False),
    ('extra-app-process-refused', ['123 ' + executable + '\n124 ' + executable], False),
]:
    state = {}; folder = work / name; folder.mkdir()
    def persist(): f.durable_json(folder / 'observations.json', state)
    def run(command, **kwargs):
        if command[0] == 'ps':
            assert tables, 'Mock sequence exhausted'
            return subprocess.CompletedProcess(command, 0, tables.pop(0), '')
        assert command[:3] == ['xcrun', 'simctl', 'terminate']
        return subprocess.CompletedProcess(command, 1, '', 'synthetic terminate failed')
    failure = None
    with patch.object(f.subprocess, 'run', side_effect=run), patch.object(f.time, 'sleep'), patch.object(f.time, 'monotonic', side_effect=[0, 0, 0, 11]):
        try:
            f.terminate_known_app(device, executable, 123, state, persist)
        except AssertionError as error:
            failure = str(error)
    assert (failure is None) is expected, (name, failure)
    assert bool(state['failureAppTermination'].get('knownAppAndInProcessWorkerAbsent')) is expected
    report['cases'].append({'case': name, 'status': 'PASS', 'mockedProcessQueries': True, 'expectedGuard': failure, 'facts': state})

# Actual caller orchestration with injected import/call/query/write failures.
# These are synthetic peers, never real PNG/native artifacts.
for name in ['retainer-import-failure', 'retainer-call-failure', 'summary-failure', 'export-failure', 'outcome-write-failure']:
    folder = work / name; folder.mkdir()
    raw, retained_base = folder / 'raw', folder / 'retained'
    raw.mkdir(); retained_base.mkdir(); stem = 'SyntheticFinalization'; prefix = 'synthetic-finalization'
    outpath = retained_base / 'outcome.json'
    (raw / (stem + '.xcresult')).mkdir()
    (raw / (stem + '.log')).write_text('synthetic host probe log')
    for extension, filename in [('PNG', 'synthetic.png'), ('JSON', 'synthetic.json')]:
        directory = raw / (stem + extension); directory.mkdir()
        (directory / filename).write_text('synthetic peer, not native evidence')
        (directory / 'manifest.json').write_text(json.dumps([{'testIdentifier': 'synthetic/test',
            'attachments': [{'exportedFileName': filename, 'suggestedHumanReadableName': 'synthetic'}]}]))
    outcome = {'nativeExit': None, 'hostError': 'synthetic injected failure', 'summary': None, 'driverExit': 1}
    f.durable_json(outpath, outcome)
    loaded = []
    spec = importlib.util.spec_from_file_location('synthetic_primary_retainer', BASE / 'retain-mixed-ineligible-results-r1.py')
    primary = importlib.util.module_from_spec(spec); spec.loader.exec_module(primary)
    def loader():
        assert outpath.exists() and json.loads(outpath.read_text())['driverExit'] == 1
        loaded.append(True)
        if name == 'retainer-import-failure': raise ImportError('synthetic loader failure')
        if name == 'retainer-call-failure':
            class Broken:
                def retain(self, *_): raise RuntimeError('synthetic retain call failure')
            return Broken()
        return primary
    queries = []
    def query(command, **kwargs):
        queries.append(command)
        assert command[:2] == ['xcrun', 'xcresulttool']
        if name == 'summary-failure' and 'summary' in command:
            return subprocess.CompletedProcess(command, 9, b'', b'synthetic summary error')
        if name == 'export-failure' and 'export' in command:
            return subprocess.CompletedProcess(command, 8, b'', b'synthetic export error')
        summary = b'{"passedTests":0,"failedTests":1,"skippedTests":0}'
        return subprocess.CompletedProcess(command, 0, summary if 'summary' in command else b'', b'')
    original_replace = f.os.replace
    failed_writes = []
    def replace(source, destination):
        if name == 'outcome-write-failure' and Path(destination) == outpath and not failed_writes:
            failed_writes.append(True)
            raise OSError('synthetic single replacement failure')
        return original_replace(source, destination)
    with patch.object(f.subprocess, 'run', side_effect=query), patch.object(f.os, 'replace', side_effect=replace):
        result, error = f.guarded_retain(loader, retained_base, raw, stem, prefix, 'synthetic-source', outcome, outpath)
    assert error and loaded and json.loads(outpath.read_text())['driverExit'] == 1
    assert len(queries) == 3, 'Every later summary/export peer attempted independently'
    if name.startswith('retainer-'):
        assert result is None and len(outcome['independentSalvage']['attempts']) == 8
        assert len(list(retained_base.glob('*fallback*'))) == 11
    else:
        assert len(result['images']) == len(result['readbacks']) == 1
        if name != 'outcome-write-failure': assert result['errors']
    if name == 'outcome-write-failure':
        assert failed_writes and outpath.with_name(outpath.name + '.emergency.json').exists()
        assert outcome['outcomePersistenceErrors']
    report['cases'].append({'case': name, 'status': 'PASS', 'injectedOrchestrationFailure': True,
        'queriesAttempted': len(queries), 'durableUnacceptedOutcome': str(outpath),
        'availableSyntheticPeersPreserved': True, 'error': error})

report['status'] = 'PASS 3 actual host children +5 mocked process guards +5 injected retention/persistence branches'
report['passed'] = len(report['cases'])
report['expectedGuards'] = sum(row.get('expectedGuard') is not None for row in report['cases'])
f.durable_json(BASE / 'capture-state-finalization-isolated-probes-r2.json', report)
print(report['status'], flush=True)
