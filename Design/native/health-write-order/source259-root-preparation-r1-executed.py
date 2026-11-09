"""Verify host correction at frozen bytes; production258 evidence is unchanged."""
from pathlib import Path
import base64, gzip, hashlib, json, time
B = Path(__file__).resolve().parent; R = B.parents[2]
load = lambda name: json.loads((B / name).read_bytes())
sha = lambda raw: hashlib.sha256(raw).hexdigest()
m = load('durable-source-r259.json'); old = load('durable-source-r258.json')
a = json.loads(gzip.decompress((B / 'durable-source-r259.json.gz').read_bytes()))
total = 0
for group, key in [('files', 'files'), ('fixtureInputs', 'binaryFiles')]:
    assert set(m[group]) == set(a[key])
    for name, fact in m[group].items():
        path = R / name; assert not path.is_symlink(); raw = path.read_bytes()
        assert len(raw) == fact['bytes'] and sha(raw) == fact['sha256'], name
        assert raw == (a[key][name].encode() if key == 'files' else base64.b64decode(a[key][name], validate=True))
        total += 1
    for name, fact in old[group].items(): assert m[group][name] == fact, name
assert m['priorModified'] == []
controls = {}
for name, count in [('source259-retained-driver-retention-r2.json', 12),
                     ('source259-retained-checker-caller-controls-r1.json', 21),
                     ('source259-runner-argument-controls-r2.json', 13)]:
    d = load(name); assert d['status'].startswith('PASS') and d['count'] == count
    if 'driver' in d: assert sha((B / d['driver']).read_bytes()) == d['driverSHA256']
    for file, fact in d.get('sources', {}).items(): assert m['files'][str(B.relative_to(R) / file)] == fact
    controls[name] = count
d = load('source259-retained-metadata-controls-r2.json')
assert d['status'].startswith('PASS') and d['metadataCount'] == 36 and d['commandCount'] == 24
assert m['files'][str(B.relative_to(R) / d['source']['file'])] == {key: d['source'][key] for key in ['bytes', 'sha256']}
controls['metadataReplay'] = 36; controls['separateSyntheticCommand'] = 24
d = load('source259-query-finalizer-controls-r2.json')
assert d['status'].startswith('PASS') and d['queryCount'] == 4 and d['finalizerCount'] == 11
for file, fact in d['sources'].items(): assert m['files'][str(B.relative_to(R) / file)] == fact
controls['queryCaller'] = 4; controls['finalizerCaller'] = 11
baseline = load('source259-retained-driver-baseline-r3.json')
assert baseline['count'] == 4 and all(row['correctRetention'] is False and row['syntheticNativeCompleted'] is True for row in baseline['cases'])
assert sha((B / baseline['driver']).read_bytes()) == baseline['driverSHA256']
core = load('source258-retained-owner-core-r5.json'); assert len(core['checks']) == 35 and all(row['passed'] is True for row in core['checks'])
full = load('source258-full-core-r3.json'); raw = gzip.decompress((B / 'source258-full-core-r3.log.gz').read_bytes())
assert full['passLines'] == 2212 and sha(raw) == full['logSHA256'] and len(raw) == full['logBytes']
for name, fact in full['sources'].items(): assert m['files'][name] == fact
for kind in ['whole-app', 'uitest']:
    d = load('source258-' + kind + '-sdk-r4.json')
    assert d['status'] == 'PASS' and d['exit'] == 0 and d['sourceFenceExact'] is True and d['sourcesBefore'] == d['sourcesAfter']
    for name, fact in d['sourcesBefore'].items():
        if name.startswith('/tmp/'):
            raw = Path(name).read_bytes(); assert len(raw) == fact['bytes'] and sha(raw) == fact['sha256']
        else: assert m['files'][name] == fact
plan = load('health-current-release-source259-r1-predeclared-plan.json'); prior = load('health-current-release-source258-r1-predeclared-plan.json')
for key in ['checkedDevelopmentMarkers', 'debugPositiveControls', 'negativeMarkersWithoutDebugPositive', 'verifiedProductionMarkers']: assert plan[key] == prior[key]
proof = load('source258-notready-exact-github.json'); assert proof['commit'] == '7f5eb5f1f52e179c670882ab6ce7bd3938d7938d' and proof['unionPaths'] == 2478
result = {'status': 'PASS frozen corrected host source and limited actual caller controls; independent180 source review pending',
          'source': m['source'], 'inputs': total, 'allPrior1101Unchanged': True, 'priorModified': [], 'controls': controls,
          'inheritedUnchangedProductionEvidence': {'source': 'durable-source-r258.json', 'core': 35, 'fullPassLines': 2212, 'wholeAppSDK': 196, 'wholeUITestSDK': 1},
          'qualifications': [
              'No new production/app/UI/core/wholeUITest source changes. Old actual258 controls are retained at exact current bytes; no new Core/SDK run invented after cache cleanup.',
              '12 producer/21 checker-main/4 query/11 finalizer are actual callers with named source/build/provider/native endpoint injections, real isolated file retention and fake images/PIDs; not native/current259 compiled-pair proof.',
              '36 metadata uses genuine historical257 file facts and current matching historical cached pair for generic schema replay only, not rerunning any old257 source-bound audit or granting current257 validity. Separate24 draft259 command controls are synthetic.',
              'Initial baseline namespace omitted STDOUT; currentR3 baseline requires actual fake-native completion and reproduces4 frozen defects. Intermediate baseline assertion and metadata Boolean aliasing failure retained and qualified.',
              'Future native/fullbuild/current2192031621/currentRelease/original visuals and raw postcommit/protected-file audits remain open. No phone, total disk-failure, global process/descriptor/reference-release, continuous visibility or fullgoal acceptance.'
          ], 'checkedAt': time.time()}
target = B / 'source259-root-preparation-r1.json'; assert not target.exists(); target.write_text(json.dumps(result, indent=2) + '\n'); print(json.dumps(result))
