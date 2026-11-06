"""Observe real SDK callback ownership; acknowledge capture without releasing it.

The first eighteen SDK callbacks are held before production gate delivery. The
SDK may already have completed. Only native Cancel/Back triggers production
store.stop; then late callbacks replay. Never claim OS-daemon cancellation timing.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import signal
import stat
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--action', choices=['Cancel', 'Back'], required=True)
args = parser.parse_args()
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
source_name = 'durable-source-r151.json'
build_name = 'health-daily-query-interrupt-r1-build.json'
source = json.loads((base / source_name).read_text())
build = json.loads((base / build_name).read_text())
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
stem = 'HealthDailyQueryInterrupt' + args.action + 'R1'
prefix = 'health-daily-query-interrupt-' + args.action.lower() + '-r1'
result = raw / (stem + '.xcresult')
assert not result.exists(), 'Do not restart an observed producer'
sha = lambda data: hashlib.sha256(data).hexdigest()

def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, 'com.dbakp.lumen', kind], text=True).strip())

def verify(installed=False):
    assert build['source'] == source_name and build['buildExit'] == 0
    for name, facts in {**source['files'], **source['fixtureInputs']}.items():
        path = repo / name
        assert path.is_file() and not path.is_symlink()
        data = path.read_bytes()
        assert len(data) == facts['bytes'] and sha(data) == facts['sha256'], name
    if installed:
        data = (container('app') / 'Lumen').read_bytes()
        assert sha(data) == build['sha256'] and len(data) == build['binaryBytes']

def files(root):
    rows = {}
    assert root.is_dir() and not root.is_symlink()
    for path in root.rglob('*'):
        facts = path.lstat()
        if stat.S_ISDIR(facts.st_mode):
            continue
        assert stat.S_ISREG(facts.st_mode) and facts.st_size < 256 * 1024
        data = path.read_bytes()
        rows[str(path.relative_to(root))] = dict(bytes=len(data), sha256=sha(data), base64=base64.b64encode(data).decode(),
                                                mode=stat.S_IMODE(facts.st_mode), inode=facts.st_ino)
    assert sum(r['bytes'] for r in rows.values()) < 8 * 1024 * 1024
    return rows

verify()
command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
    '-destination', 'platform=iOS Simulator,id=' + device, '-derivedDataPath', '/tmp/LumenBatch37Simulator',
    '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
    '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
    '-only-testing:LumenUITests/LumenSmokeTests/testDailyCacheHealthQuery' + args.action,
    '-resultBundlePath', str(result), 'test-without-building']
log = raw / (stem + '.log')
audit = dict(source=source_name, build=build_name, driverSHA256=sha(Path(__file__).read_bytes()), action=args.action,
    status='running', scope=__doc__)
acknowledged = False
started = time.time()
with log.open('xb') as output:
    process = subprocess.Popen(command, cwd=repo, stdout=output, stderr=subprocess.STDOUT)
    subprocess.Popen(['caffeinate', '-d', '-i', '-w', str(process.pid)])
    audit['producerPID'] = process.pid
    try:
        while process.poll() is None:
            assert time.time() - started < 240, 'Finite producer deadline'
            if not acknowledged:
                try:
                    group = container('group.com.dbakp.lumen')
                    checkpoint = group / 'Lumen-daily-query-interruption.json'
                    if checkpoint.stat().st_mtime < started:
                        time.sleep(0.2)
                        continue
                    held = json.loads(checkpoint.read_bytes())
                except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
                    time.sleep(0.2)
                    continue
                if len(held['held']) == 18 and "Added attachment named 'daily-query-held'" in log.read_text():
                    verify(installed=True)
                    assert len(held['executed']) == 18 and set(held['held']) == set(held['executed'])
                    assert held['stopped'] == [] and not held['released'] and held['lateDelivered'] == 0
                    root, prior = group / 'LumenData', group / 'LumenData.previous'
                    before, previous = files(root), files(prior)
                    assert len(before) == 16 and len(previous) == 9
                    assert base64.b64decode(before['today.json']['base64']) == b'{"syntheticUnavailableToday":'
                    assert not (group / 'Lumen-daily-cache-health-query.json').exists() or (group / 'Lumen-daily-cache-health-query.json').stat().st_mtime < started
                    journal = json.loads(base64.b64decode(before['health-write-intent.json']['base64']))
                    assert {e['action'] for e in journal['events']} == {'save', 'delete'} and len(journal['events']) == 2
                    assert all(e['acknowledged'] == [] for e in journal['events'])
                    audit.update(held=held, before=before, previousBefore=previous)
                    (group / 'Lumen-daily-query-observed.json').write_text('{"observed":true}')
                    acknowledged = True
            elif 'stopped' not in audit:
                state = json.loads(checkpoint.read_bytes())
                if state['lateDelivered'] == 18:
                    assert state['released'] and state['hostObserved'] and state['held'] == []
                    assert set(state['stopped']) == set(state['executed']) == set(audit['held']['executed'])
                    assert files(root) == before and files(prior) == previous
                    query = group / 'Lumen-daily-cache-health-query.json'
                    assert not query.exists() or query.stat().st_mtime < started, 'Cancelled result published'
                    audit.update(stopped=state, currentExactAfterLateCallbacks=True, previousExactAfterLateCallbacks=True)
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
assert acknowledged and 'stopped' in audit
verify(installed=True)
assert files(root) == before and files(prior) == previous
query = group / 'Lumen-daily-cache-health-query.json'
assert query.stat().st_mtime >= started
fresh = json.loads(query.read_bytes())
assert fresh['requestCompleted'] and len(fresh['metrics']['readings']) == 18
assert all(r['healthQuery']['outcome'] == 'noData' and r['components'] == [] for r in fresh['metrics']['readings'].values())
(base / (prefix + '-fresh-sdk-query.json')).write_bytes(query.read_bytes())
readbacks = json.loads((base / (prefix + '-readbacks.json')).read_text())
assert len(readbacks) == 1
native = json.loads((base / readbacks[0]['file']).read_text())
assert native['action'] == args.action and native['stoppedSeconds'] < 3
assert all(native[k] is True for k in ['firstResultNeverReviewed', 'freshReviewReached', 'retryNotNow', 'finalParent'])
audit.update(status='passed:18 actual SDK handles stopped;18 late callbacks ignored; fresh actual review; all16current/9prior exact',
    after=files(root), previousAfter=files(prior), native=native, currentExactAfterFreshReview=True, previousExactAfterFreshReview=True)
(base / (prefix + '-host-audit.json')).write_text(json.dumps(audit, indent=2) + '\n')
print('PASS', args.action, '18 actual SDK handles stopped; late callbacks ignored; fresh review;16current/9prior exact', flush=True)
