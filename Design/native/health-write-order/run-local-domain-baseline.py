"""Serial native defect baselines with independent live-file/source readback.

Passing this driver means the pre-repair behavior was observed as declared.
It does not mean corrupt-domain handling is repaired.
"""
import base64
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys

base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = '922E011C-3895-4DB1-9C9A-1D3A977226CF'
source_name = sys.argv[1]
build_name = sys.argv[2]
source = json.loads((base / source_name).read_text())
build = json.loads((base / build_name).read_text())
cases = [('water', 'CorruptWater'), ('meals', 'CorruptMeals'),
         ('goals', 'CorruptGoals'), ('unreadable-water', 'UnreadableWater')]
progress = {'status': 'running', 'completed': [], 'source': source_name, 'build': build_name}

def digest(data):
    return hashlib.sha256(data).hexdigest()

def snapshot(**fields):
    progress.update(fields)
    progress['updatedAtUTC'] = datetime.now(timezone.utc).isoformat()
    (raw / 'LocalDomainBaselineProgressR1.json').write_text(json.dumps(progress, indent=2) + '\n')

def output(*command):
    return subprocess.check_output(command, cwd=repo).decode().strip()

def run(command, log):
    with log.open('wb') as stream:
        process = subprocess.Popen(command, cwd=repo, stdout=stream, stderr=subprocess.STDOUT)
        snapshot(runningPID=process.pid)
        result = process.wait()
    snapshot(runningPID=None)
    (base / ('Durable' + log.name + '.gz')).write_bytes(gzip.compress(log.read_bytes(), mtime=0))
    if result:
        snapshot(status='failed', failedLog=str(log), exitCode=result)
        raise RuntimeError(f'{log}: exit {result}')

for domain, test in cases:
    stem = 'LocalDomain' + test + 'BaselineR1'
    result = raw / (stem + '.xcresult')
    assert not result.exists(), 'Never overwrite a previous native result bundle'
    snapshot(case=domain, step='native XCTest')
    print('START:', domain, flush=True)
    run(['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
         '-destination', 'platform=iOS Simulator,id=' + device,
         '-derivedDataPath', '/tmp/LumenBatch37Simulator',
         '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages',
         '-disableAutomaticPackageResolution', '-parallel-testing-enabled', 'NO',
         '-only-testing:LumenUITests/LumenSmokeTests/testHealthLocal' + test + 'Baseline',
         '-resultBundlePath', str(result), 'test-without-building'], raw / (stem + '.log'))
    assert '** TEST EXECUTE SUCCEEDED **' in (raw / (stem + '.log')).read_text()
    snapshot(step='independent live host readback')
    app_data = Path(output('xcrun', 'simctl', 'get_app_container', device, 'com.dbakp.lumen', 'data'))
    group = Path(output('xcrun', 'simctl', 'get_app_container', device, 'com.dbakp.lumen', 'group.com.dbakp.lumen'))
    app = Path(output('xcrun', 'simctl', 'get_app_container', device, 'com.dbakp.lumen', 'app'))
    report = json.loads((app_data / 'tmp/Lumen-local-data-baseline.json').read_bytes())
    assert report['status'] == 'Local data baseline recorded' and report['domain'] == domain
    assert report['checks'] and all(row['passed'] for row in report['checks'])
    saved = {}
    for name, encoded in report['persistedFiles'].items():
        data = (group / 'LumenData' / name).read_bytes()
        assert data == base64.b64decode(encoded), name
        saved[name] = {'bytes': len(data), 'sha256': digest(data)}
    if domain == 'unreadable-water':
        assert (group / 'LumenData/water.json').is_dir()
        assert report['directoryRetained'] and report['readError'] and report['mutationError']
        assert not report['external'] and not report['trace']
    else:
        name = domain + '.json'
        assert (group / 'LumenData' / name).read_bytes() != base64.b64decode(report['originalDamagedBytes'])
        journal = json.loads((group / 'LumenData/health-write-intent.json').read_bytes())
        assert len(journal['events']) == 1
        event = journal['events'][0]
        assert set(event['acknowledged']) == {row['metric'] for row in event['components']}
        assert event['action'] == 'save' and not event.get('issue')
        external = {f"com.dbakp.lumen.health.v1.{journal['owner']}.{event['id']}.{row['metric']}": row['value']
                    for row in event['components']}
        assert external == report['external']
        if domain == 'water':
            water = json.loads((group / 'LumenData/water.json').read_bytes())
            assert len(water) == 1 and water[0]['ml'] == 137 and not report['loadedWaterIDs']
        elif domain == 'meals':
            meals = json.loads((group / 'LumenData/meals.json').read_bytes())
            assert {row['id'] for row in meals} == {'synthetic-stale-legacy-meal', 'synthetic-new-corrupt-baseline-meal'}
            assert report['loadedMealIDs'] == ['synthetic-stale-legacy-meal']
        else:
            assert report['loadedWeight'] == 61.25
            assert json.loads((group / 'LumenData/goals.json').read_bytes())['weightKg'] == report['savedWeight'] == 76.25
    for name, facts in source['files'].items():
        assert digest((repo / name).read_bytes()) == facts['sha256'], name
    binary_hash = digest((app / 'Lumen').read_bytes())
    assert binary_hash == build['sha256'] and build['source'] == source_name
    label = 'local-domain-' + domain + '-baseline-r1'
    (base / (label + '-report.json')).write_text(json.dumps(report, indent=2) + '\n')
    audit = {'status': 'declared pre-repair behavior independently observed', 'case': domain,
             'source': source_name, 'build': build_name, 'nativeChecks': len(report['checks']),
             'hostMatchedFiles': saved, 'installedBinarySHA256': binary_hash,
             'scope': 'Actual current native saved files match the diagnostic bytes; controlled adapter identities and receipts independently reconstructed. Corrupt cases reproduce an unresolved defect; unreadable-directory behavior is not device-lock permission coverage.'}
    (base / (label + '-host-audit.json')).write_text(json.dumps(audit, indent=2) + '\n')
    snapshot(step='export native originals')
    run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result),
         '--output-path', str(raw / (stem + 'Attachments')), '--filter', '*.png'], raw / (stem + 'Export.log'))
    progress['completed'].append({'domain': domain, 'checks': len(report['checks']), 'label': label})
    snapshot(step='case complete')
    print('RECORDED:', domain, len(report['checks']), 'native checks and exact host-file comparison', flush=True)
snapshot(status='recorded', step='all four pre-repair cases observed')
print('RECORDED: three corrupt-domain replacement defects and one real unreadable-directory baseline.', flush=True)
