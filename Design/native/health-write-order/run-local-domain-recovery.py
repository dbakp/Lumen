"""Native rejection -> independent damaged-file readback -> checked recovery.

The approval file only releases a synthetic test barrier. It is not user consent
or an app recovery feature. No original rejected file is repaired before readback.
"""
import argparse
import base64
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

parser = argparse.ArgumentParser()
parser.add_argument('--source', required=True)
parser.add_argument('--build', required=True)
parser.add_argument('--trial', default='R1')
parser.add_argument('--cases', nargs='+')
args = parser.parse_args()
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = '922E011C-3895-4DB1-9C9A-1D3A977226CF'
cases = [(domain, after, test + ('AfterOpen' if after else 'Recovery'))
         for after in [False, True]
         for domain, test in [('water', 'Water'), ('meals', 'Meals'), ('workouts', 'Workouts'),
                              ('goals', 'Goals'), ('today', 'Today'), ('unreadable-water', 'Unreadable')]
         if not (after and domain == 'unreadable-water')]
if args.cases:
    cases = [row for row in cases if row[2] in args.cases]
    assert len(cases) == len(args.cases)
source = json.loads((base / args.source).read_text())
build = json.loads((base / args.build).read_text())
progress = {'status': 'running', 'source': args.source, 'build': args.build, 'completed': []}

def digest(data):
    return hashlib.sha256(data).hexdigest()

def snapshot(**fields):
    progress.update(fields)
    progress['updatedAtUTC'] = datetime.now(timezone.utc).isoformat()
    (raw / ('LocalDomainRecoveryProgress' + args.trial + '.json')).write_text(json.dumps(progress, indent=2) + '\n')

def output(*command):
    return subprocess.check_output(command, cwd=repo).decode().strip()

def container(kind):
    return Path(output('xcrun', 'simctl', 'get_app_container', device, 'com.dbakp.lumen', kind))

def source_matches():
    for name, facts in source['files'].items():
        assert digest((repo / name).read_bytes()) == facts['sha256'], name
    binary = container('app') / 'Lumen'
    assert digest(binary.read_bytes()) == build['sha256'] and build['source'] == args.source

def retain(log):
    (base / (log.name + '.gz')).write_bytes(gzip.compress(log.read_bytes(), mtime=0))

for domain, after_open, test in cases:
    stem = 'LocalDomain' + test + args.trial
    result = raw / (stem + '.xcresult')
    assert not result.exists(), 'Never overwrite previous native results'
    group = container('group.com.dbakp.lumen')
    checkpoint_path = group / 'Lumen-local-data-checkpoint.json'
    approval_path = group / 'Lumen-local-data-readback.json'
    for path in [checkpoint_path, approval_path]:
        assert not path.is_symlink(), 'Do not follow or remove symlinks'
        if path.exists():
            assert path.is_file()
            path.unlink()  # Only these two known disposable test protocol files.
    snapshot(case=test, step='native XCTest and damaged-file checkpoint', runningPID=None)
    print('START:', test, flush=True)
    command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
               '-destination', 'platform=iOS Simulator,id=' + device,
               '-derivedDataPath', '/tmp/LumenBatch37Simulator',
               '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
               '-parallel-testing-enabled', 'NO', '-only-testing:LumenUITests/LumenSmokeTests/testHealthLocal' + test,
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
                    if value['domain'] == domain and value['afterOpen'] == after_open:
                        checkpoint = value
                        break
                time.sleep(0.25)
            assert checkpoint is not None, 'Native checkpoint missing; inspect this same producer/log before considering another run'
            snapshot(step='host reads rejected bytes before recovery')
            assert checkpoint['checks'] and all(row['passed'] for row in checkpoint['checks'])
            assert not checkpoint['trace'] and checkpoint['issue']
            rejected = {}
            root = group / 'LumenData'
            for name, encoded in checkpoint['files'].items():
                actual = (root / name).read_bytes()
                assert actual == base64.b64decode(encoded), name
                rejected[name] = {'bytes': len(actual), 'sha256': digest(actual)}
            for name in checkpoint['missing']:
                assert not (root / name).exists(), name
            if checkpoint.get('directory'):
                assert (root / checkpoint['directory']).is_dir()
            else:
                damaged = (root / (domain + '.json')).read_bytes()
                assert damaged == b'{"syntheticDamagedHistory": ['
                try:
                    json.loads(damaged)
                    raise AssertionError('Synthetic damaged current JSON unexpectedly valid')
                except json.JSONDecodeError:
                    pass
            source_matches()
            label = 'local-domain-' + test.lower() + '-' + args.trial.lower()
            (base / (label + '-checkpoint.json')).write_text(json.dumps(checkpoint, indent=2) + '\n')
            first_audit = {'status': 'matched before recovery', 'test': test, 'source': args.source,
                           'build': args.build, 'nonce': checkpoint['nonce'], 'files': rejected,
                           'missing': checkpoint['missing'], 'directory': checkpoint.get('directory'),
                           'nativePreRecoveryChecks': len(checkpoint['checks']), 'trace': checkpoint['trace']}
            (base / (label + '-rejected-host-audit.json')).write_text(json.dumps(first_audit, indent=2) + '\n')
            approval_path.write_text(json.dumps(checkpoint['nonce']) + '\n')
            snapshot(step='native healthy independence and checked recovery')
            code = process.wait(timeout=150)
        retain(log)
        snapshot(runningPID=None)
        assert code == 0 and '** TEST EXECUTE SUCCEEDED **' in log.read_text(), str(log)
        report = json.loads((container('data') / 'tmp/Lumen-local-data-repair-report.json').read_bytes())
        assert report['status'] == 'Saved-data checks passed'
        assert report['checkpoint'] == checkpoint and all(row['passed'] for row in report['checks'])
        final = {}
        for name, encoded in report['persistedFiles'].items():
            actual = (root / name).read_bytes()
            assert actual == base64.b64decode(encoded), name
            final[name] = {'bytes': len(actual), 'sha256': digest(actual)}
        journal = json.loads((root / 'health-write-intent.json').read_bytes())
        external = {}
        for event in journal['events']:
            assert event['action'] == 'save' and not event.get('issue')
            assert set(event['acknowledged']) == {row['metric'] for row in event['components']}
            external.update({f"com.dbakp.lumen.health.v1.{journal['owner']}.{event['id']}.{row['metric']}": row['value'] for row in event['components']})
        assert external == report['external'] and not report.get('issue')
        for name, key in [('water', 'liveWaterIDs'), ('meals', 'liveMealIDs'), ('workouts', 'liveWorkoutIDs')]:
            assert [row['id'] for row in json.loads((root / (name + '.json')).read_bytes())] == report[key]
        assert json.loads((root / 'goals.json').read_bytes())['weightKg'] == report['liveWeight']
        source_matches()
        (base / (label + '-report.json')).write_text(json.dumps(report, indent=2) + '\n')
        (base / (label + '-recovered-host-audit.json')).write_text(json.dumps({
            'status': 'matched after recovery', 'test': test, 'nativeChecks': len(report['checks']),
            'source': args.source, 'build': args.build, 'files': final,
            'externalComponents': len(external), 'installedBinarySHA256': build['sha256'],
            'scope': 'Host compared actual rejected files before release of the test barrier, then actual recovered files, live IDs, controlled external identities/receipts and installed source/binary. No HealthKit/UI/device acceptance.'}, indent=2) + '\n')
        export_log = raw / (stem + 'Export.log')
        with export_log.open('wb') as stream:
            subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result),
                            '--output-path', str(raw / (stem + 'Attachments')), '--filter', '*.png'],
                           stdout=stream, stderr=subprocess.STDOUT, check=True)
        retain(export_log)
        progress['completed'].append({'test': test, 'domain': domain, 'afterOpen': after_open,
                                      'checks': len(report['checks']), 'label': label})
        snapshot(step='case complete')
        print('PASS:', test, len(report['checks']), 'native checks; rejected and recovered files independently matched', flush=True)
    except Exception as error:
        retain(log)
        snapshot(status='failed', error=str(error), runningPID=process.pid if process.poll() is None else None)
        raise
snapshot(status='passed', step='all requested native rejection/recovery cases complete', runningPID=None)
print('PASS:', len(cases), 'native cases with host readback before every recovery.', flush=True)
