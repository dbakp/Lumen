"""Replay every frozen pre-repair invalid payload through native store recovery.

The host reads the rejected bytes before releasing a test-only recovery barrier.
Both startup and post-open damage use the exact baseline payload bytes.
"""
import argparse
import base64
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--source', required=True)
parser.add_argument('--build', required=True)
parser.add_argument('--trial', default='R1')
args = parser.parse_args()
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = '922E011C-3895-4DB1-9C9A-1D3A977226CF'
baseline = json.loads((base / 'local-values-baseline-r1-report.json').read_text())
cases = baseline['acceptedInvalidCases']
assert len(cases) == 15
source = json.loads((base / args.source).read_text())
build = json.loads((base / args.build).read_text())
progress = {'status': 'running', 'source': args.source, 'build': args.build, 'completed': []}

def digest(data):
    return hashlib.sha256(data).hexdigest()

def snapshot(**fields):
    progress.update(fields)
    progress['updatedAtUTC'] = datetime.now(timezone.utc).isoformat()
    (raw / ('LocalValuesNativeProgress' + args.trial + '.json')).write_text(json.dumps(progress, indent=2) + '\n')

def container(kind):
    return Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, 'com.dbakp.lumen', kind]).decode().strip())

def source_matches():
    for name, facts in source['files'].items():
        assert digest((repo / name).read_bytes()) == facts['sha256'], name
    assert digest((container('app') / 'Lumen').read_bytes()) == build['sha256']
    assert build['source'] == args.source

def retain(log):
    (base / (log.name + '.gz')).write_bytes(gzip.compress(log.read_bytes(), mtime=0))

for after_open in [False, True]:
    for index, row in enumerate(cases):
        phase = 'AfterOpen' if after_open else 'Startup'
        stem = f'LocalValuesNativeCase{index:02d}{phase}{args.trial}'
        label = f'local-values-case{index:02d}-{phase.lower()}-{args.trial.lower()}'
        result = raw / (stem + '.xcresult')
        assert not result.exists(), 'Never overwrite existing result bundles'
        group = container('group.com.dbakp.lumen')
        checkpoint_path = group / 'Lumen-local-data-checkpoint.json'
        approval_path = group / 'Lumen-local-data-readback.json'
        fixture_path = group / 'Lumen-local-semantic-fixture.json'
        for path in [checkpoint_path, approval_path, fixture_path]:
            assert not path.is_symlink()
            if path.exists():
                assert path.is_file()
                path.unlink()  # These three transient test coordination files only.
        fixture = {'label': row['case'], 'domain': row['domain'], 'afterOpen': after_open, 'bytes': row['currentBytes']}
        fixture_path.write_text(json.dumps(fixture) + '\n')
        snapshot(case=row['case'], index=index, phase=phase, step='native XCTest', runningPID=None)
        print('START:', index, phase, row['case'], flush=True)
        command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
                   '-destination', 'platform=iOS Simulator,id=' + device,
                   '-derivedDataPath', '/tmp/LumenBatch37Simulator',
                   '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
                   '-parallel-testing-enabled', 'NO', '-only-testing:LumenUITests/LumenSmokeTests/testHealthLocalSemanticRecovery',
                   '-resultBundlePath', str(result), 'test-without-building']
        log = raw / (stem + '.log')
        try:
            with log.open('wb') as stream:
                process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT, cwd=repo)
                snapshot(runningPID=process.pid)
                deadline = time.monotonic() + 180
                checkpoint = None
                while process.poll() is None and time.monotonic() < deadline:
                    if checkpoint_path.exists():
                        value = json.loads(checkpoint_path.read_bytes())
                        if value.get('inputCase') == row['case'] and value['domain'] == row['domain'] and value['afterOpen'] == after_open:
                            checkpoint = value
                            break
                    time.sleep(0.25)
                assert checkpoint is not None, 'Native checkpoint missing; inspect this same process/log before any new run'
                snapshot(step='host reads rejected semantic payload before recovery')
                assert checkpoint['checks'] and all(x['passed'] for x in checkpoint['checks'])
                assert checkpoint['issue'] and not checkpoint['trace']
                root = group / 'LumenData'
                rejected = {}
                for name, data in checkpoint['files'].items():
                    actual = (root / name).read_bytes()
                    assert actual == base64.b64decode(data), name
                    rejected[name] = {'bytes': len(actual), 'sha256': digest(actual)}
                for name in checkpoint['missing']:
                    assert not (root / name).exists(), name
                payload = (root / (row['domain'] + '.json')).read_bytes()
                assert payload == base64.b64decode(row['currentBytes'])
                json.loads(payload)  # Valid JSON; the rejected defect is in record values/identity.
                assert not checkpoint.get('directory')
                source_matches()
                (base / (label + '-checkpoint.json')).write_text(json.dumps(checkpoint, indent=2) + '\n')
                first = {'status': 'matched before recovery', 'case': row['case'], 'domain': row['domain'], 'phase': phase,
                         'source': args.source, 'build': args.build, 'nonce': checkpoint['nonce'],
                         'baselineExactPayloadSHA256': digest(payload), 'files': rejected,
                         'missing': checkpoint['missing'], 'nativePreRecoveryChecks': len(checkpoint['checks'])}
                (base / (label + '-rejected-host-audit.json')).write_text(json.dumps(first, indent=2) + '\n')
                approval_path.write_text(json.dumps(checkpoint['nonce']) + '\n')
                snapshot(step='native checked recovery and invalid-new-payload rejection')
                code = process.wait(timeout=150)
            retain(log)
            snapshot(runningPID=None)
            assert code == 0 and '** TEST EXECUTE SUCCEEDED **' in log.read_text(), str(log)
            report = json.loads((container('data') / 'tmp/Lumen-local-data-repair-report.json').read_bytes())
            assert report['status'] == 'Saved-data checks passed' and report['checkpoint'] == checkpoint
            assert all(x['passed'] for x in report['checks']) and not report.get('issue')
            final = {}
            for name, data in report['persistedFiles'].items():
                actual = (root / name).read_bytes()
                assert actual == base64.b64decode(data), name
                final[name] = {'bytes': len(actual), 'sha256': digest(actual)}
            journal = json.loads((root / 'health-write-intent.json').read_bytes())
            external = {}
            for event in journal['events']:
                assert event['action'] == 'save' and not event.get('issue')
                assert set(event['acknowledged']) == {x['metric'] for x in event['components']}
                external.update({f"com.dbakp.lumen.health.v1.{journal['owner']}.{event['id']}.{x['metric']}": x['value'] for x in event['components']})
            assert external == report['external']
            for name, key in [('water', 'liveWaterIDs'), ('meals', 'liveMealIDs'), ('workouts', 'liveWorkoutIDs')]:
                assert [x['id'] for x in json.loads((root / (name + '.json')).read_bytes())] == report[key]
            assert json.loads((root / 'goals.json').read_bytes())['weightKg'] == report['liveWeight']
            source_matches()
            (base / (label + '-report.json')).write_text(json.dumps(report, indent=2) + '\n')
            final_audit = {'status': 'matched after recovery', 'case': row['case'], 'domain': row['domain'], 'phase': phase,
                           'source': args.source, 'build': args.build, 'nativeChecks': len(report['checks']),
                           'files': final, 'externalComponents': len(external), 'installedBinarySHA256': build['sha256'],
                           'scope': 'Actual rejected baseline bytes matched before barrier release; actual recovered files/live values and controlled adapter receipts matched afterward. Not HealthKit, UI or device acceptance.'}
            (base / (label + '-recovered-host-audit.json')).write_text(json.dumps(final_audit, indent=2) + '\n')
            export = raw / (stem + 'Export.log')
            with export.open('wb') as stream:
                subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result),
                                '--output-path', str(raw / (stem + 'Attachments')), '--filter', '*.png'],
                               stdout=stream, stderr=subprocess.STDOUT, check=True)
            retain(export)
            progress['completed'].append({'index': index, 'case': row['case'], 'domain': row['domain'],
                                          'phase': phase, 'checks': len(report['checks']), 'label': label})
            snapshot(step='case complete')
            print('PASS:', index, phase, row['case'], len(report['checks']), 'checks; exact baseline bytes and recovered files matched', flush=True)
        except Exception as error:
            retain(log)
            snapshot(status='failed', error=str(error), runningPID=process.pid if process.poll() is None else None)
            raise
snapshot(status='passed', step='all 30 frozen-payload native cases complete', runningPID=None)
print('PASS: all 15 frozen invalid payloads at startup and after open, with pre-recovery host readback.', flush=True)
