"""Run all eighteen frozen128 cases sequentially; stop on any failure."""
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import time

base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
ledger = base / 'health-import-denied-matrix-pending-r2-producer.json'
assert not ledger.exists(), 'Never overwrite a producer ledger or restart an observed producer'
contract = json.loads((base / 'health-import-denied-matrix-r6-contract.json').read_text())
pending = contract['requiredCases']
order = sorted(pending, key=lambda c: (
    0 if c['mode'] == 'largest' else 1,
    ['readable', 'legacy', 'encrypted'].index(c['format']),
    ['compact', 'main'].index(c['device']),
    ['normal', 'dark', 'largest'].index(c['mode'])))
assert len(order) == 18 == contract['caseCount']
assert {tuple(sorted(c.items())) for c in order} == {tuple(sorted(c.items())) for c in pending}
state = {'status': 'running', 'source': 'durable-source-r128.json',
    'build': 'health-import-denied-matrix-native-build-r5.json',
    'contract': 'health-import-denied-matrix-r6-contract.json',
    'wrapperSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'plannedCases': order, 'results': [], 'startedUnix': time.time(),
    'scope': 'Same archived fault driver, all gates unchanged; sequential native producers to avoid AX contention. No source edits, case skipping or retry inside this wrapper.'}

def save():
    ledger.write_text(json.dumps(state, indent=2) + '\n')

save()
for case in order:
    device, kind, mode = case['device'], case['format'], case['mode']
    stem = 'HealthImportDeniedMatrix' + device.title() + kind.title() + mode.title() + 'R6'
    prefix = 'health-import-denied-matrix-' + device + '-' + kind + '-' + mode + '-r6'
    assert not (raw / (stem + '.xcresult')).exists()
    state['currentCase'] = case
    save()
    print('START ' + stem, flush=True)
    command = ['python3', str(base / 'run-health-import-denied-matrix.py'),
        '--source', state['source'], '--build', state['build'],
        '--device', device, '--case', kind, '--mode', mode, '--trial', 'R6']
    with (raw / (stem + 'Driver.log')).open('wb') as output:
        process = subprocess.Popen(command, cwd=repo, stdout=output, stderr=subprocess.STDOUT)
        state['currentDriverPID'] = process.pid
        save()
        code = process.wait()
    row = {**case, 'stem': stem, 'prefix': prefix, 'driverExit': code,
        'driverPID': process.pid, 'producerTerminal': True}
    state['results'].append(row)
    save()
    for extension, pattern in [('PNG', '*.png'), ('JSON', '*.json')]:
        with (raw / (stem + extension + 'Export.log')).open('wb') as output:
            exported = subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments',
                '--path', str(raw / (stem + '.xcresult')),
                '--output-path', str(raw / (stem + extension)), '--filter', pattern],
                cwd=repo, stdout=output, stderr=subprocess.STDOUT)
        row[extension.lower() + 'ExportExit'] = exported.returncode
        save()
        if exported.returncode:
            state['status'] = 'stopped: attachment export failed'
            save()
            raise SystemExit(exported.returncode)
    command = ['python3', str(base / 'retain-health-record-attachments.py'),
        '--stem', stem, '--prefix', prefix, '--source', state['source'],
        '--png-dir', str(raw / (stem + 'PNG')), '--json-dir', str(raw / (stem + 'JSON'))]
    if code:
        command.append('--include-failed-trial')
    subprocess.run(command, cwd=repo, check=True)
    row['attachmentsRetained'] = True
    save()
    print('END ' + stem + ' driverExit=' + str(code), flush=True)
    if code:
        state['status'] = 'stopped: native/host case failed; no later cases started'
        save()
        raise SystemExit(code)
state['status'] = 'terminal: all18 native/host cases and attachment exports passed; visual review pending'
state['finishedUnix'] = time.time()
state.pop('currentCase', None)
state.pop('currentDriverPID', None)
save()
print(state['status'], flush=True)
