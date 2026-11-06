"""One actual native corrupt-cache clear, with independent live/prior audits.

The release file advances a DEBUG barrier inside the real transaction worker.
It does not confirm the user's action or substitute any product file writes.
"""
import base64
import argparse
import gzip
import hashlib
import json
import re
import signal
import stat
import subprocess
import time
from pathlib import Path

base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
parser = argparse.ArgumentParser()
parser.add_argument('--source', required=True)
parser.add_argument('--build', required=True)
parser.add_argument('--trial', required=True)
args = parser.parse_args()
assert re.fullmatch(r'R[1-9][0-9]*', args.trial)
source_name = args.source
build_name = args.build
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
stem = 'HealthDailyCacheClearCorrupt' + args.trial
prefix = 'health-daily-cache-clear-corrupt-' + args.trial.lower()
result = raw / (stem + '.xcresult')
assert not result.exists(), 'Never restart an observed native producer'
source = json.loads((base / source_name).read_text())
build = json.loads((base / build_name).read_text())
sha = lambda data: hashlib.sha256(data).hexdigest()

def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, 'com.dbakp.lumen', kind], text=True).strip())

def verify(installed=False):
    assert build['source'] == source_name and build['buildExit'] == 0
    for name, facts in {**source['files'], **source['fixtureInputs']}.items():
        data = (repo / name).read_bytes()
        assert len(data) == facts['bytes'] and sha(data) == facts['sha256'], name
    if installed:
        data = (container('app') / 'Lumen').read_bytes()
        assert len(data) == build['binaryBytes'] and sha(data) == build['sha256']

def files(root):
    rows, total = {}, 0
    assert root.is_dir() and not root.is_symlink()
    for path in root.rglob('*'):
        facts = path.lstat()
        if stat.S_ISDIR(facts.st_mode):
            continue
        assert stat.S_ISREG(facts.st_mode) and facts.st_size < 256 * 1024, path
        data = path.read_bytes(); total += len(data)
        assert total < 8 * 1024 * 1024
        rows[str(path.relative_to(root))] = dict(bytes=len(data), sha256=sha(data),
            base64=base64.b64encode(data).decode(), mode=stat.S_IMODE(facts.st_mode), inode=facts.st_ino)
    return rows

verify()
command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
    '-destination', 'platform=iOS Simulator,id=' + device, '-derivedDataPath', '/tmp/LumenBatch37Simulator',
    '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
    '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
    '-only-testing:LumenUITests/LumenSmokeTests/testDailyCacheClearCorrupt',
    '-resultBundlePath', str(result), 'test-without-building']
log = raw / (stem + '.log')
audit = dict(source=source_name, build=build_name, driverSHA256=sha(Path(__file__).read_bytes()),
    status='running', scope='First main/light explicit corrupt-cache clear only; full parent cache/UI/HealthKit/device scope remains.')
started = time.time(); released = False
with log.open('xb') as output:
    process = subprocess.Popen(command, cwd=repo, stdout=output, stderr=subprocess.STDOUT)
    subprocess.Popen(['caffeinate', '-d', '-i', '-w', str(process.pid)])
    audit['producerPID'] = process.pid
    try:
        while process.poll() is None:
            assert time.time() - started < 260, 'Finite native test deadline'
            if not released:
                try:
                    group = container('group.com.dbakp.lumen')
                    checkpoint = group / 'Lumen-health-cancel-checkpoint.json'
                    if checkpoint.stat().st_mtime < started:
                        time.sleep(0.2); continue
                    state = json.loads(checkpoint.read_bytes())
                except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
                    time.sleep(0.2); continue
                if state.get('attempts') and "Added attachment named 'daily-cache-clear-held'" in log.read_text():
                    record = state['attempts'][0]
                    assert len(state['attempts']) == 1 and record['ordinal'] == 1 and record['phase'] == 'held'
                    assert record['workerControlMatchesUI'] and not record['uiCancelled']
                    assert re.fullmatch(r'LumenData\.restore-[A-Fa-f0-9-]+', record['stage'])
                    verify(installed=True)
                    root = group / 'LumenData'; prior = group / 'LumenData.previous'
                    before = files(root); previous = files(prior)
                    assert base64.b64decode(before['today.json']['base64']) == b'{"syntheticUnavailableToday":'
                    assert all(base64.b64decode(before[name]['base64']) == base64.b64decode(encoded) for name, encoded in record['originals'].items())
                    journal = json.loads(base64.b64decode(before['health-write-intent.json']['base64']))
                    assert len(journal['events']) == 2 and {e['action'] for e in journal['events']} == {'save', 'delete'}
                    assert all(e['acknowledged'] == [] for e in journal['events'])
                    assert not any(name.startswith('.health-cache-history/') for name in before)
                    assert (group / record['stage']).is_dir()
                    audit.update(before=before, previousBefore=previous, held=record, stageExistsBeforeRelease=True)
                    temporary = group / ('Lumen-cache-release-' + record['nonce'] + '.tmp')
                    temporary.write_text(json.dumps({'nonce': record['nonce']}))
                    temporary.replace(group / 'Lumen-health-cancel-release.json')
                    released = True
                    audit['releasedAfterActualHeldCapture'] = True
                    (base / (prefix + '-host-audit.json')).write_text(json.dumps(audit, indent=2) + '\n')
            time.sleep(0.2)
        code = process.wait()
        audit['producerExitCode'] = code
    except BaseException as error:
        audit['observationError'] = repr(error)
        if process.poll() is None:
            process.send_signal(signal.SIGINT)
            try: process.wait(timeout=45)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
        audit['producerExitCode'] = process.returncode
        raise
    finally:
        (base / (prefix + '-host-audit.json')).write_text(json.dumps(audit, indent=2) + '\n')

summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result)], text=True))
(raw / (stem + '-summary.json')).write_text(json.dumps(summary, indent=2) + '\n')
for extension, pattern in [('PNG', '*.png'), ('JSON', '*.json')]:
    with (raw / (stem + extension + 'Export.log')).open('xb') as output:
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result),
            '--output-path', str(raw / (stem + extension)), '--filter', pattern], stdout=output, stderr=subprocess.STDOUT, check=True)
retain = ['python3', str(base / 'retain-health-record-attachments.py'), '--stem', stem, '--prefix', prefix,
          '--source', source_name, '--png-dir', str(raw / (stem + 'PNG')), '--json-dir', str(raw / (stem + 'JSON'))]
if code: retain.append('--include-failed-trial')
subprocess.run(retain, cwd=repo, check=True)
assert code == 0 and summary['passedTests'] == 1 and summary['failedTests'] == summary['skippedTests'] == 0
assert released
verify(installed=True)
after, previous_after = files(root), files(prior)
assert previous_after == previous
for name, facts in before.items():
    if name != 'today.json': assert after[name] == facts, name
assert all(name.startswith(('.health-cache-history/', '.health-recovery/')) for name in set(after) - set(before))
current = json.loads(base64.b64decode(after['today.json']['base64']))
assert current['readings'] == {} and current['recordedTotalKeys'] == [] and current['excludesLumenNutrition'] is True
assert any(name.startswith('.health-recovery/') and name.endswith('/today.json')
           and facts['sha256'] == before['today.json']['sha256'] for name, facts in after.items())
receipts = [name for name in after if name.startswith('.health-cache-history/')]
assert len(receipts) == 1
receipt = json.loads(base64.b64decode(after[receipts[0]]['base64']))
assert receipt['action'] == 'clear' and receipt['owner'] == journal['owner']
assert receipt['prior']['state'] == 'unavailable' and receipt['prior']['entries']['']['digest'] == before['today.json']['sha256']
assert receipt['rawDigest'] == after['today.json']['sha256']
deadline = time.monotonic() + 5
while (group / audit['held']['stage']).exists() and time.monotonic() < deadline: time.sleep(0.1)
assert not (group / audit['held']['stage']).exists()
audit.update(status='passed: actual native explicit clear installs unknown snapshot; exact current/prior/raw/journal and receipt preservation matched',
    after=after, previousAfter=previous_after, stageAbsentAfterCommit=True, receipt=receipt)
(base / (prefix + '-host-audit.json')).write_text(json.dumps(audit, indent=2) + '\n')
print('PASS native clear: current', len(before), 'previous', len(previous), 'files preserved; pending save/deletion exact', flush=True)
