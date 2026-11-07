"""Observe an actual native directory-cache clear; never substitute product writes."""
import base64
import gzip
import hashlib
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import time

base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
stem = 'HealthDailyCacheDirectoryClearR1'
prefix = 'health-daily-cache-directory-clear-r1'
source_name = 'durable-source-r165.json'
build_name = prefix + '-build.json'
source = json.loads((base / source_name).read_text())
build = json.loads((base / build_name).read_text())
result = raw / (stem + '.xcresult')
log = raw / (stem + '.log')
assert not result.exists() and not log.exists(), 'Do not restart a native producer'
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

def tree(root):
    assert root.is_dir() and not root.is_symlink()
    rows, total = {}, 0
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(directory) / name
            facts = path.lstat()
            assert stat.S_ISDIR(facts.st_mode) or stat.S_ISREG(facts.st_mode), path
            row = dict(kind='directory' if stat.S_ISDIR(facts.st_mode) else 'file',
                       mode=facts.st_mode, device=facts.st_dev, inode=facts.st_ino,
                       bytes=facts.st_size, modifiedNS=facts.st_mtime_ns)
            if row['kind'] == 'file':
                assert facts.st_size < 256 * 1024
                data = path.read_bytes(); total += len(data)
                assert total < 8 * 1024 * 1024
                row.update(sha256=sha(data), base64=base64.b64encode(data).decode())
            rows[str(path.relative_to(root))] = row
    return rows

def stable_tree(root):
    first = tree(root)
    assert tree(root) == first, 'Live tree changed during capture'
    return first

verify()
command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
           '-destination', 'platform=iOS Simulator,id=' + device,
           '-derivedDataPath', '/tmp/LumenBatch37Simulator', '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages',
           '-disableAutomaticPackageResolution', '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
           '-only-testing:LumenUITests/LumenSmokeTests/testDailyCacheClearDirectory',
           '-resultBundlePath', str(result), 'test-without-building']
audit = dict(status='running', source=source_name, build=build_name, driverSHA256=sha(Path(__file__).read_bytes()),
             scope='Main/light/standard synthetic directory-cache clear only; no Health sample or physical-phone actions.')
started = time.time(); initial = None; not_now = False; released = False; error = None
with log.open('xb') as output:
    process = subprocess.Popen(command, cwd=repo, stdout=output, stderr=subprocess.STDOUT)
    subprocess.Popen(['caffeinate', '-d', '-i', '-w', str(process.pid)])
    audit['nativePID'] = process.pid
    print('Native directory clear running PID', process.pid, flush=True)
    try:
        while process.poll() is None:
            assert time.time() - started < 300, 'Finite native case deadline'
            text = log.read_text(errors='replace')
            if initial is None and "Added attachment named 'daily-cache-directory-initial'" in text:
                assert "Added attachment named 'daily-cache-directory-clear-review'" not in text
                group = container('group.com.dbakp.lumen'); root = group / 'LumenData'; prior = group / 'LumenData.previous'
                initial, previous = stable_tree(root), stable_tree(prior)
                assert "Added attachment named 'daily-cache-directory-clear-review'" not in log.read_text(errors='replace')
                assert initial['today.json']['kind'] == initial['today.json/nested']['kind'] == 'directory'
                assert base64.b64decode(initial['today.json/nested/raw-a.bin']['base64']) == bytes([0, 17, 255, 42])
                assert base64.b64decode(initial['today.json/raw-b.txt']['base64']) == b'Synthetic damaged directory snapshot.\n'
                assert not any(k.startswith(('.health-recovery/', '.health-cache-history/')) for k in initial)
                audit.update(before=initial, previousBefore=previous, initialCapturedBeforeClearReview=True)
            if initial is not None and not not_now and "Added attachment named 'daily-cache-directory-clear-not-now'" in text:
                assert "Added attachment named 'daily-cache-directory-clear-held'" not in text
                assert stable_tree(root) == initial and stable_tree(prior) == previous
                assert "Added attachment named 'daily-cache-directory-clear-held'" not in log.read_text(errors='replace')
                not_now = True; audit['notNowPreservedExactTree'] = True
            if not_now and not released and "Added attachment named 'daily-cache-directory-clear-held'" in text:
                state = json.loads((group / 'Lumen-health-cancel-checkpoint.json').read_bytes())
                assert len(state['attempts']) == 1
                held = state['attempts'][0]
                assert held['ordinal'] == 1 and held['phase'] == 'held' and held['workerControlMatchesUI'] and not held['uiCancelled']
                assert stable_tree(root) == initial and stable_tree(prior) == previous
                assert all(base64.b64decode(v) == base64.b64decode(initial[k]['base64']) for k, v in held['originals'].items())
                assert held['stage'].startswith('LumenData.restore-') and '/' not in held['stage']
                assert (group / held['stage']).is_dir()
                verify(installed=True)
                audit.update(held=held, heldTreeExactBeforeRelease=True)
                temporary = group / ('Lumen-directory-release-' + held['nonce'] + '.tmp')
                temporary.write_text(json.dumps({'nonce': held['nonce']}))
                temporary.replace(group / 'Lumen-health-cancel-release.json')
                released = True; audit['releasedAfterActualHeldCapture'] = True
            (base / (prefix + '-host-audit.json')).write_text(json.dumps(audit, indent=2) + '\n')
            time.sleep(0.1)
    except BaseException as caught:
        error = caught; audit['observationError'] = repr(caught)
        if process.poll() is None:
            process.send_signal(signal.SIGINT)
            try: process.wait(timeout=45)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
    code = process.wait(); audit['nativeExitCode'] = code

# Retain actual attachments and terminal logs even when an expectation fails.
try:
    summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result)], text=True))
    (base / (prefix + '-summary.json')).write_text(json.dumps(summary, indent=2) + '\n')
    for extension, pattern in [('PNG', '*.png'), ('JSON', '*.json')]:
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(raw / (stem + extension)), '--filter', pattern], check=True, stdout=subprocess.DEVNULL)
    retain = ['python3', str(base / 'retain-health-record-attachments.py'), '--stem', stem, '--prefix', prefix, '--source', source_name,
              '--png-dir', str(raw / (stem + 'PNG')), '--json-dir', str(raw / (stem + 'JSON'))]
    if code or error: retain.append('--include-failed-trial')
    subprocess.run(retain, cwd=repo, check=True)
    assert error is None, repr(error)
    assert code == 0 and summary['passedTests'] == 1 and summary['failedTests'] == summary['skippedTests'] == 0
    assert initial is not None and not_now and released
    verify(installed=True)
    after = stable_tree(root); previous_after = stable_tree(prior)
    assert previous_after == previous
    for name, facts in initial.items():
        if name == 'today.json' or name.startswith('today.json/'): continue
        assert name in after and after[name]['kind'] == facts['kind']
        if facts['kind'] == 'file': assert after[name] == facts, name
        else: assert after[name]['mode'] == facts['mode'], name
    current = json.loads(base64.b64decode(after['today.json']['base64']))
    assert after['today.json']['kind'] == 'file' and current['readings'] == {} and current['recordedTotalKeys'] == [] and current['excludesLumenNutrition'] is True
    assert not any(k.startswith('today.json/') for k in after)
    copies = [k for k, v in after.items() if k.startswith('.health-recovery/') and k.endswith('/today.json') and v['kind'] == 'directory']
    assert len(copies) == 1
    for name, facts in initial.items():
        if name != 'today.json' and not name.startswith('today.json/'): continue
        copied = after[copies[0] + name[len('today.json'):]]
        assert copied['kind'] == facts['kind'] and copied['mode'] == facts['mode'], name
        if facts['kind'] == 'file': assert copied['sha256'] == facts['sha256'] and copied['base64'] == facts['base64']
    for name in set(after) - set(initial):
        assert name.startswith(('.health-cache-history/', '.health-recovery/')), name
    receipts = [k for k, v in after.items() if k.startswith('.health-cache-history/') and v['kind'] == 'file']
    assert len(receipts) == 1
    receipt = json.loads(base64.b64decode(after[receipts[0]]['base64']))
    journal = json.loads(base64.b64decode(initial['health-write-intent.json']['base64']))
    assert receipt['action'] == 'clear' and receipt['owner'] == journal['owner'] and receipt['prior']['state'] == 'unavailable'
    expected_entries = {k[len('today.json'):].lstrip('/'): v for k, v in initial.items() if k == 'today.json' or k.startswith('today.json/')}
    assert set(receipt['prior']['entries']) == set(expected_entries)
    for name, facts in expected_entries.items():
        entry = receipt['prior']['entries'][name]
        assert entry['mode'] == facts['mode'] and entry['inode'] == facts['inode'] and entry['size'] == facts['bytes']
        assert entry.get('digest') == facts.get('sha256')
    assert receipt['rawDigest'] == after['today.json']['sha256']
    assert not (group / audit['held']['stage']).exists()
    audit.update(status='PASS native directory clear and independent tree/private-copy/receipt audit', after=after, previousAfter=previous_after,
                 receipt=receipt, privateDirectoryCopy=copies[0], stageAbsentAfterCommit=True)
except BaseException as caught:
    error = caught; audit.update(status='FAILED; retained actual native and host evidence', observationError=repr(caught))
finally:
    data = log.read_bytes(); archive = stem + '.log.gz'; (base / archive).write_bytes(gzip.compress(data, mtime=0))
    audit['nativeLog'] = dict(archive=archive, bytes=len(data), sha256=sha(data))
    (base / (prefix + '-host-audit.json')).write_text(json.dumps(audit, indent=2) + '\n')
print(audit['status'], flush=True)
if error: raise error
