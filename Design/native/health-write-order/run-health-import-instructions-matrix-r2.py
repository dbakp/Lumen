"""Continue all18 frozen131 cases after the separately executed compact-largest case."""
import hashlib
import json
from pathlib import Path
import subprocess
import time

base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
ledger = base / 'health-import-instructions-matrix-r2-producer.json'
assert not ledger.exists(), 'Never overwrite or restart an observed producer'
contract = json.loads((base / 'health-import-instructions-matrix-r2-contract.json').read_text())
source = contract['source']
build = contract['build']
first = {'device': 'compact', 'format': 'readable', 'mode': 'largest'}
first_prefix = 'health-import-denied-matrix-compact-readable-largest-r9'
summary = json.loads((base / (first_prefix + '-summary.json')).read_text())
audit = json.loads((base / (first_prefix + '-host-audit.json')).read_text())
assert summary['passedTests'] == 1 and summary['failedTests'] == summary['skippedTests'] == 0
assert audit['source'] == source and audit['build'] == build and audit['producerExitCode'] == 0
assert audit['status'].startswith('passed:')
assert (base / (first_prefix + '-images.json')).exists()
assert (base / (first_prefix + '-readbacks.json')).exists()
planned = contract['requiredCases']
assert len(planned) == 18 == contract['caseCount'] and first in planned
pending = [case for case in planned if case != first]
order = sorted(pending, key=lambda c: (
    0 if c['mode'] == 'largest' else 1,
    ['readable', 'legacy', 'encrypted'].index(c['format']),
    ['compact', 'main'].index(c['device']),
    ['normal', 'dark', 'largest'].index(c['mode'])))
assert len(order) == 17
state = {'status': 'running', 'source': source, 'build': build,
    'contract': 'health-import-instructions-matrix-r2-contract.json',
    'wrapperSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'plannedCases': planned, 'results': [{**first,
        'stem': 'HealthImportDeniedMatrixCompactReadableLargestR9',
        'prefix': first_prefix, 'driverExit': 0, 'producerTerminal': True,
        'pngExportExit': 0, 'jsonExportExit': 0, 'attachmentsRetained': True,
        'executionBoundary': 'Actual separately completed131case, session85993; not a historical129carry'}],
    'startedUnix': time.time(),
    'scope': 'All18 actual131cases. Same archived fault driver, no weakened gates. '
             'One already executed131case plus17sequential fresh cases. Stop on failure; '
             'no source edits, case retries or cleanup while active. Visual acceptance separate.'}

def save():
    ledger.write_text(json.dumps(state, indent=2) + '\n')

save()
for case in order:
    device, kind, mode = case['device'], case['format'], case['mode']
    stem = 'HealthImportDeniedMatrix' + device.title() + kind.title() + mode.title() + 'R9'
    prefix = 'health-import-denied-matrix-' + device + '-' + kind + '-' + mode + '-r9'
    assert not (raw / (stem + '.xcresult')).exists()
    state['currentCase'] = case
    save()
    print('START ' + stem, flush=True)
    command = ['python3', str(base / 'run-health-import-denied-matrix.py'),
        '--source', source, '--build', build, '--device', device,
        '--case', kind, '--mode', mode, '--trial', 'R9']
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
        '--stem', stem, '--prefix', prefix, '--source', source,
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
state['status'] = 'terminal: all18 actual131native/host cases and exports passed; visual review pending'
state['finishedUnix'] = time.time()
state.pop('currentCase', None)
state.pop('currentDriverPID', None)
save()
print(state['status'], flush=True)
