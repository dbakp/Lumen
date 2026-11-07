"""Finite actual Settings enable/restore capability with normal and intentional throwing bodies."""
import gzip
import hashlib
import json
from pathlib import Path
import signal
import subprocess
import time

base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch44Checks')
stem = 'HealthReduceMotionCapabilityR1'
prefix = 'health-reduce-motion-capability-r1'
source_name = 'durable-source-r190.json'
build_name = 'health-recovery-motion-enabled-r1-build.json'
source = json.loads((base / source_name).read_text())
build = json.loads((base / build_name).read_text())
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
result = raw / (stem + '.xcresult')
assert not result.exists()


def identity():
    for group in ['files', 'fixtureInputs']:
        for name, row in source[group].items():
            data = (repo / name).read_bytes()
            assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256'], name
    assert build['source'] == source_name and build['buildExit'] == 0
    app = Path('/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/Lumen.app/Lumen')
    assert hashlib.sha256(app.read_bytes()).hexdigest() == build['sha256']
    assert hashlib.sha256(Path(build['testBinary']).read_bytes()).hexdigest() == build['testBinarySHA256']


identity()
command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen',
           '-configuration', 'Debug', '-destination', 'platform=iOS Simulator,id=' + device,
           '-derivedDataPath', '/tmp/LumenBatch37Simulator',
           '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages',
           '-disableAutomaticPackageResolution', '-parallel-testing-enabled', 'NO',
           '-collect-test-diagnostics', 'never',
           '-only-testing:LumenUITests/LumenSmokeTests/testReduceMotionSettingsCapability',
           '-resultBundlePath', str(result), 'test-without-building']
timed_out = False
with (raw / (stem + '.log')).open('xb') as stream:
    process = subprocess.Popen(command, cwd=repo, stdout=stream, stderr=subprocess.STDOUT)
    subprocess.Popen(['caffeinate', '-d', '-i', '-w', str(process.pid)])
    print('Simulator Reduce Motion enable/restore capability PID', process.pid, flush=True)
    try:
        code = process.wait(timeout=240)
    except subprocess.TimeoutExpired:
        timed_out = True
        process.send_signal(signal.SIGINT)
        try:
            code = process.wait(timeout=45)
        except subprocess.TimeoutExpired:
            process.kill()
            code = process.wait()

# Preserve the actual outcome before assertions; failures never become skips.
log = (raw / (stem + '.log')).read_bytes()
(base / (stem + '.log.gz')).write_bytes(gzip.compress(log, mtime=0))
outcome = {'source': source_name, 'build': build_name, 'device': device,
           'producerPID': process.pid, 'exitCode': code, 'timedOut': timed_out,
           'checkedAt': time.time(), 'scope': 'Settings enable/restore capability only; no motion behavior acceptance'}
(base / (prefix + '-outcome.json')).write_text(json.dumps(outcome, indent=2) + '\n')
summary = json.loads(subprocess.check_output(
    ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result)], text=True))
(raw / (stem + '-summary.json')).write_text(json.dumps(summary, indent=2) + '\n')
for suffix, pattern in [('PNG', '*.png'), ('JSON', '*.json')]:
    subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result),
                    '--output-path', str(raw / (stem + suffix)), '--filter', pattern], check=True)
retain = ['python3', str(base / 'retain-health-record-attachments.py'), '--stem', stem,
          '--prefix', prefix, '--source', source_name, '--png-dir', str(raw / (stem + 'PNG')),
          '--json-dir', str(raw / (stem + 'JSON')), '--raw-root', str(raw)]
if code or summary['failedTests']:
    retain.append('--include-failed-trial')
subprocess.run(retain, cwd=repo, check=True)
identity()
assert not timed_out and code == 0
assert summary['passedTests'] == 1 and summary['failedTests'] == summary['skippedTests'] == 0
readbacks = json.loads((base / (prefix + '-readbacks.json')).read_text())
assert len(readbacks) == 2
reports = [json.loads((base / row['file']).read_text()) for row in readbacks]
assert sum(r['failure'] is None for r in reports) == 1
assert sum(r['failure'] is not None and 'LumenExpectedMotionBodyFailure' in r['failure'] for r in reports) == 1
for report in reports:
    assert report['phase'] == 'terminal' and report['restored'] and report['restorationError'] is None
    assert report['original'] == report['finalUIKitReduceMotion']
    samples = report['samples']
    assert [v['phase'] for v in samples] == ['original', 'enabled', 'restored']
    assert samples[0]['uikit'] == samples[2]['uikit'] == report['original']
    assert samples[1]['uikit'] is True and samples[1]['switch'] == '1'
    assert samples[2]['switch'] == ('1' if report['original'] else '0')
outcome.update(status='PASS actual Reduce Motion enable/readback/original restoration on normal and deliberate Swift throwing-body exits; teardown-abort/full motion behavior unverified',
               originalSettings=[r['original'] for r in reports], nativeJSON=[r['file'] for r in readbacks])
(base / (prefix + '-outcome.json')).write_text(json.dumps(outcome, indent=2) + '\n')
print(json.dumps(outcome), flush=True)
