"""One actual native mixed/zero HealthKit cache rebuild, with independent live/prior audits.

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
device = '922E011C-3895-4DB1-9C9A-1D3A977226CF'
stem = 'HealthDailyDetailsCompactLargest' + args.trial
prefix = 'health-daily-details-compact-largest-' + args.trial.lower()
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
    '-only-testing:LumenUITests/LumenSmokeTests/testDailyCacheRebuildHealthKitRecordedLargestDetails',
    '-resultBundlePath', str(result), 'test-without-building']
log = raw / (stem + '.log')
audit = dict(source=source_name, build=build_name, driverSHA256=sha(Path(__file__).read_bytes()),
    status='running', scope='Actual simulator HealthKit18-query rebuild and native readonly values/confirmation/commit; broader HealthKit/permissions/faults/device scope remains.')
started = time.time(); released = False
with log.open('xb') as output:
    process = subprocess.Popen(command, cwd=repo, stdout=output, stderr=subprocess.STDOUT)
    subprocess.Popen(['caffeinate', '-d', '-i', '-w', str(process.pid)])
    audit['producerPID'] = process.pid
    try:
        while process.poll() is None:
            assert time.time() - started < 2100, 'Finite native test deadline'
            if not released:
                try:
                    group = container('group.com.dbakp.lumen')
                    checkpoint = group / 'Lumen-health-cancel-checkpoint.json'
                    if checkpoint.stat().st_mtime < started:
                        time.sleep(0.2); continue
                    state = json.loads(checkpoint.read_bytes())
                except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
                    time.sleep(0.2); continue
                if state.get('attempts') and "Added attachment named 'daily-cache-health-held'" in log.read_text():
                    record = state['attempts'][0]
                    assert len(state['attempts']) == 1 and record['ordinal'] == 1 and record['phase'] == 'held'
                    assert record['workerControlMatchesUI'] and not record['uiCancelled']
                    assert re.fullmatch(r'LumenData\.restore-[A-Fa-f0-9-]+', record['stage'])
                    verify(installed=True)
                    seed_path = group / 'Lumen-daily-cache-recorded-fixture.json'
                    assert seed_path.stat().st_mtime >= started
                    seed = json.loads(seed_path.read_bytes())
                    assert seed['status'] == 'seeded' and seed['remaining'] == 4
                    samples = seed['samples']
                    assert len(samples) == len({s['uuid'] for s in samples}) == 4
                    assert all(s['sourceBundle'] == 'com.dbakp.lumen' for s in samples)
                    expected_samples = [('HKQuantityTypeIdentifierStepCount', 0), ('HKQuantityTypeIdentifierBodyMass', 76.25),
                                        ('HKQuantityTypeIdentifierHeartRate', 64), ('HKQuantityTypeIdentifierHeartRate', 80)]
                    assert [(s['identifier'], s['value']) for s in samples] == expected_samples
                    assert seed['tag'].startswith('LumenSyntheticDailyCache-')
                    audit['actualSavedSampleReadbacks'] = seed
                    (base / (prefix + '-seeded.json')).write_bytes(seed_path.read_bytes())
                    access_path = group / 'Lumen-daily-cache-health-access.json'
                    query_path = group / 'Lumen-daily-cache-health-query.json'
                    assert access_path.stat().st_mtime >= started and query_path.stat().st_mtime >= started
                    access = json.loads(access_path.read_bytes()); observed = json.loads(query_path.read_bytes())
                    assert access['requestCompleted'] and access['available'] and access['connected'] and access['readPermissionInferred'] is False
                    assert observed['requestCompleted']
                    keys = {'steps','activeEnergy','restingEnergy','exercise','stand','water','restingHR','hrv','spo2','weight','respiratoryRate','vo2max','heartRate','bodyFat','calories','protein','carbs','fat'}
                    assert set(observed['metrics']['readings']) == keys
                    for key, reading in observed['metrics']['readings'].items():
                        outcome = reading['healthQuery']['outcome']
                        assert outcome in {'recorded', 'noData', 'failed'}
                        assert reading['healthQuery']['start'] == observed['start'] and reading['healthQuery']['end'] == observed['end']
                        assert bool(reading['components']) == (outcome == 'recorded')
                        assert all(c['origin'] == 'healthKit' and c['value'] >= 0 for c in reading['components'])
                    for name, path in [('sdk-access', access_path), ('sdk-query', query_path)]:
                        (base / (prefix + '-' + name + '.json')).write_bytes(path.read_bytes())
                    audit.update(actualSDKAccess=access, actualSDKQuery=observed,
                                 sdkQueryRawSHA256=sha(query_path.read_bytes()), sdkQueryRawBytes=query_path.stat().st_size)
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
assert current == observed['metrics'] and current['excludesLumenNutrition'] is True
assert any(name.startswith('.health-recovery/') and name.endswith('/today.json')
           and facts['sha256'] == before['today.json']['sha256'] for name, facts in after.items())
receipts = [name for name in after if name.startswith('.health-cache-history/')]
assert len(receipts) == 1
receipt = json.loads(base64.b64decode(after[receipts[0]]['base64']))
assert receipt['action'] == 'rebuild' and receipt['owner'] == journal['owner']
assert receipt['prior']['state'] == 'unavailable' and receipt['prior']['entries']['']['digest'] == before['today.json']['sha256']
assert receipt['rawDigest'] == after['today.json']['sha256']
deadline = time.monotonic() + 5
while (group / audit['held']['stage']).exists() and time.monotonic() < deadline: time.sleep(0.1)
assert not (group / audit['held']['stage']).exists()
# Predeclared independent checks for SDK empty-error normalization and genuine errors.
callbacks = observed['callbacks']
assert len(callbacks) == 18
statistics = [c for c in callbacks if c['kind'] == 'statistics']
assert len(statistics) == 10
assert sum(c.get('errorDomain') == 'com.apple.healthkit' and c.get('errorCode') == 11 for c in statistics) == 8
expected_values = {'steps': 0, 'weight': 76.25, 'heartRate': 72}
for key, reading in observed['metrics']['readings'].items():
    if key in expected_values:
        assert reading['healthQuery']['outcome'] == 'recorded' and len(reading['components']) == 1
        assert abs(reading['components'][0]['value'] - expected_values[key]) < 1e-8, (key, reading)
        assert reading['components'][0]['origin'] == 'healthKit'
    else:
        assert reading['healthQuery']['outcome'] == 'noData' and reading['components'] == [], key
assert len(observed['callbacks']) == 18
expected = {'empty-success': ('noData', None), 'SDK-no-data': ('noData', None),
            'no-data-with-quantity': ('noData', None), 'database-locked': ('failed', None),
            'authorization-denied': ('failed', None), 'other-domain-same-code': ('failed', None),
            'transport-cancelled': ('failed', None), 'recorded-zero': ('recorded', 0), 'recorded-value': ('recorded', 137.25)}
controls = {c['name']: c for c in observed['normalizationChecks']}
assert set(controls) == set(expected) and len(observed['normalizationChecks']) == 9
for name, (outcome, value) in expected.items():
    assert controls[name]['outcome'] == outcome and controls[name].get('value') == value, name
assert controls['SDK-no-data']['errorDomain'] == 'com.apple.healthkit' and controls['SDK-no-data']['errorCode'] == 11
assert controls['other-domain-same-code']['errorDomain'] == 'synthetic-other-domain' and controls['other-domain-same-code']['errorCode'] == 11
audit.update(actualSDKNoDataNormalizationVerified=True, normalizationControlsVerified=9)
audit.update(status='passed: actual SDK query metrics equal committed raw snapshot; current/prior/raw/Health intent exact',
    after=after, previousAfter=previous_after, stageAbsentAfterCommit=True, receipt=receipt)
(base / (prefix + '-host-audit.json')).write_text(json.dumps(audit, indent=2) + '\n')
print('PASS actual SDK rebuild: current', len(before), 'previous', len(previous), 'files preserved; pending save/deletion exact', flush=True)

readbacks = json.loads((base / (prefix + '-readbacks.json')).read_text())
assert len(readbacks) == 1
native = json.loads((base / readbacks[0]['file']).read_text())
assert set(native['reviewedValues']) == keys and native['savedLabel'] == 'Saved snapshot rebuilt'
for key, reading in observed['metrics']['readings'].items():
    if reading['healthQuery']['outcome'] != 'recorded': assert native['reviewedValues'][key] == 'Not recorded'
    else: assert native['reviewedValues'][key] != 'Not recorded'
audit['actualOutcomeCounts'] = {kind: sum(v['healthQuery']['outcome'] == kind for v in observed['metrics']['readings'].values()) for kind in ['recorded','noData','failed']}
audit['all18NativeValueStatesMatchActualQuery'] = True
(base / (prefix + '-host-audit.json')).write_text(json.dumps(audit, indent=2) + '\n')
print('Actual SDK outcomes', audit['actualOutcomeCounts'], flush=True)

# Final Back from the saved screen starts fixture-only exact source/tag/UUID cleanup.
cleanup_deadline = time.monotonic() + 10
while time.monotonic() < cleanup_deadline:
    cleanup = json.loads(seed_path.read_bytes())
    if cleanup['status'] == 'cleaned': break
    time.sleep(0.1)
assert cleanup['status'] == 'cleaned' and cleanup['remaining'] == 0
assert cleanup['tag'] == seed['tag'] and cleanup['samples'] == seed['samples']
(base / (prefix + '-cleaned.json')).write_bytes(seed_path.read_bytes())
# Existing private intent must match the exact original root journal too.
originals = [name for name, facts in after.items() if name.startswith('.health-recovery/') and name.endswith('/today.json') and facts['base64'] == before['today.json']['base64']]
assert len(originals) == 1
intent_name = originals[0].rsplit('/', 1)[0] + '/device-intent.json'
assert after[intent_name]['base64'] == before['health-write-intent.json']['base64']
assert len({name.split('/')[1] for name in after if name.startswith('.health-recovery/')}) == 2
assert native['reviewedValues']['steps'] == '0 steps'
assert native['reviewedValues']['heartRate'] == '72 bpm'
weight_label = native['reviewedValues']['weight']
assert re.fullmatch(r'76[.,]25 kg', weight_label), weight_label
assert float(weight_label.removesuffix(' kg').replace(',', '.')) == expected_values['weight']
audit.update(exactFourSampleCleanup=cleanup, damagedSnapshotAdjacentIntentExact=True, privateCopies=2,
    actualRecordedValues=expected_values, status='passed: actual3recorded/15noData/0failed including measured zero; exact snapshot/current/prior/intent; four fixture samples cleaned')
(base / (prefix + '-host-audit.json')).write_text(json.dumps(audit, indent=2) + '\n')
print('PASS actual recorded values', expected_values, 'four exact SDK samples cleaned', flush=True)

# Full largest-text metadata/paragraph captures are mandatory, not a value-only run.
assert native['largestDetailsRequested'] is True
assert set(native['fullDetails']) == keys and set(native['valueHeights']) == keys
assert native['valueHeights']['steps'] > 40
required_prefixes = {'daily-initial-state', 'daily-initial-backup-scope', 'daily-review-consequence'}
required_prefixes |= {'daily-review-' + name for name in ['dailyCacheRetainedConsequence', 'dailyCacheReturnedCount', 'dailyCacheNoDataCount', 'dailyCacheFailedCount', 'dailyCacheQueryFrom', 'dailyCacheQueryThrough', 'dailyCacheQueryScope']}
for key, detail in native['fullDetails'].items():
    fields = {'Heading', 'Outcome', 'Checked', 'Start', 'End'}
    if key in expected_values: fields |= {'Source', 'Period'}
    assert set(detail) == fields and all(isinstance(v, str) and v.strip() for v in detail.values()), key
    assert detail['Outcome'] == ('Reading returned' if key in expected_values else 'No data returned'), key
    required_prefixes.add('daily-detail-' + key + '-value')
    required_prefixes |= {'daily-detail-' + key + '-' + field.lower() for field in fields}
coverage = {}
for match in re.finditer(r'Identifier capture ([A-Za-z0-9-]+) part([0-9]+): ([0-9.]+)\.\.\.([0-9.]+) of ([0-9.]+) points', log.read_text()):
    name, part, lower, upper, height = match.groups()
    coverage.setdefault(name, []).append(dict(part=int(part), lower=float(lower), upper=float(upper), height=float(height)))
assert required_prefixes <= set(coverage), sorted(required_prefixes - set(coverage))
images = json.loads((base / (prefix + '-images.json')).read_text())
for name in required_prefixes:
    rows = coverage[name]
    assert [r['part'] for r in rows] == list(range(1, len(rows) + 1))
    covered = 0
    for row in rows:
        assert row['lower'] <= covered + 2 and row['upper'] > row['lower']
        covered = max(covered, row['upper'])
        assert any(r['metadata']['suggestedHumanReadableName'].startswith(name + '-part' + str(row['part']) + '_') for r in images)
    assert covered >= rows[-1]['height'] - 2, name
audit.update(fullLargestDetailsRequiredPrefixes=len(required_prefixes), nativeCoverage=coverage,
    status='passed: compact largest/dark actual recorded rebuild; full native capture intervals and all metadata controls;25file preservation and exact4sample cleanup')
(base / (prefix + '-host-audit.json')).write_text(json.dumps(audit, indent=2) + '\n')
print('PASS compact largest/dark full detail prefixes', len(required_prefixes), 'native captures', len(images), flush=True)

previous_path = group / 'Lumen-daily-cache-previous-fixture-cleanup.json'
assert previous_path.stat().st_mtime >= started
recovered = json.loads(previous_path.read_bytes())
interrupted = json.loads((base / 'health-daily-details-compact-largest-r6-interrupted-seed.json').read_bytes())
assert recovered['tag'] == interrupted['tag'] and recovered['samples'] == interrupted['samples']
assert recovered['status'] == 'cleaned-after-interrupted-test' and recovered['remaining'] == 0
assert recovered['tag'] != seed['tag']
(base / (prefix + '-previous-fixture-cleaned.json')).write_bytes(previous_path.read_bytes())
audit.update(interrupted158FourSamplesCleaned=recovered)
(base / (prefix + '-host-audit.json')).write_text(json.dumps(audit, indent=2) + '\n')
print('PASS four interrupted158 exact SDK samples cleaned before current seed', flush=True)
