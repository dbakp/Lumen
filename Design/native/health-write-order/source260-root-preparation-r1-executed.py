"""Verify frozen typed-provenance correction and unchanged production evidence."""
from pathlib import Path
import base64, gzip, hashlib, json, time
B = Path(__file__).resolve().parent; R = B.parents[2]
load = lambda name: json.loads((B / name).read_bytes())
sha = lambda raw: hashlib.sha256(raw).hexdigest()
m = load('durable-source-r260.json'); old = load('durable-source-r259.json')
a = json.loads(gzip.decompress((B / 'durable-source-r260.json.gz').read_bytes()))
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
for name, expected in [('source260-driver-caller-controls-r1.json', 12), ('source260-checker-types-controls-r1.json', 33),
                       ('source260-strict-fact-controls-r1.json', 54), ('source260-preflight-caller-controls-r1.json', 20),
                       ('source260-runner-argument-controls-r1.json', 13)]:
    d = load(name); assert d['status'].startswith('PASS') and d['count'] == expected
    if 'driver' in d: assert sha((B / d['driver']).read_bytes()) == d['driverSHA256']
    for file, fact in d.get('sources', {}).items(): assert m['files'][str(B.relative_to(R) / file)] == fact
    if isinstance(d.get('source'), dict):
        fact = d['source']; assert m['files'][str(B.relative_to(R) / fact['file'])] == {key: fact[key] for key in ['bytes', 'sha256']}
    controls[name] = expected
d = load('source260-query-finalizer-controls-r1.json'); assert d['status'].startswith('PASS') and d['queryCount'] == 4 and d['finalizerCount'] == 11
for file, fact in d['sources'].items(): assert m['files'][str(B.relative_to(R) / file)] == fact
controls['queryCaller'] = 4; controls['finalizerMain'] = 11
baseline = load('source260-checker-types-baseline-r1.json')
assert baseline['count'] == 33 and sum(row['accepted'] is True for row in baseline['cases']) == 12
current = load('source260-checker-types-controls-r1.json'); assert sum(row['accepted'] is True for row in current['cases']) == 1
core = load('source258-retained-owner-core-r5.json'); assert len(core['checks']) == 35 and all(row['passed'] is True for row in core['checks'])
full = load('source258-full-core-r3.json'); raw = gzip.decompress((B / 'source258-full-core-r3.log.gz').read_bytes())
assert full['passLines'] == 2212 and len(raw) == full['logBytes'] and sha(raw) == full['logSHA256']
for name, fact in full['sources'].items(): assert m['files'][name] == fact
for kind in ['whole-app', 'uitest']:
    d = load('source258-' + kind + '-sdk-r4.json')
    assert d['status'] == 'PASS' and d['exit'] == 0 and d['sourceFenceExact'] is True and d['sourcesBefore'] == d['sourcesAfter']
    for name, fact in d['sourcesBefore'].items():
        if name.startswith('/tmp/'):
            raw = Path(name).read_bytes(); assert len(raw) == fact['bytes'] and sha(raw) == fact['sha256']
        else: assert m['files'][name] == fact
plan = load('health-current-release-source260-r1-predeclared-plan.json'); prior = load('health-current-release-source259-r1-predeclared-plan.json')
for key in ['checkedDevelopmentMarkers', 'debugPositiveControls', 'negativeMarkersWithoutDebugPositive', 'verifiedProductionMarkers']: assert plan[key] == prior[key]
assert [len(plan[key]) for key in ['checkedDevelopmentMarkers', 'debugPositiveControls', 'negativeMarkersWithoutDebugPositive', 'verifiedProductionMarkers']] == [219, 203, 16, 21]
proof = load('source259-notready-exact-github.json'); assert proof['commit'] == '66c19ef003c6b5ccde09bb6745de34614db7baf2' and proof['unionPaths'] == 2516
advisory = load('source260-advisory-readonly-r1.json'); assert advisory['sourceReady'] is False and advisory['runtimeAcceptance'] is False
result = {'status': 'PASS frozen typed host correction and scoped controls; independent181 source review pending',
          'source': m['source'], 'inputs': total, 'allPrior1137Unchanged': True, 'priorModified': [], 'controls': controls,
          'inheritedUnchangedProductionEvidence': {'source': 'durable-source-r258.json', 'core': 35, 'fullPassLines': 2212, 'wholeAppSDK': 196, 'wholeUITestSDK': 1},
          'qualifications': [
              'Advisory before freeze found no remaining concrete blocker; it is not formal181 sourceReady or runtime acceptance.',
              'Actual caller33/12/query4/finalizer11 use named fake source/preflight/proof/Git/provider/native endpoints, real isolated retention and synthetic image/PID data. No current260 pair/pixels/native proof.',
              'Actual strict54 and preflight20 use genuine historical257 receipts/manifest/archive/matching historical cached pair and three Git blobs only as schema/integrity fixtures. Preflight historical SOURCE/BUILD context and source-verifier callback explicitly injected. No old257 source-bound native audit or current257 validity claim.',
              'Retained generic originals permit strict int0 for empty diagnostic peers; selected app/test/log/trace sizes and final PID are positive ints. All scalar aliases in the tested family reject.',
              'All app/model/UI/core/wholeUITest source bytes unchanged258. Core35/full2212/fencedSDKR4 evidence is inherited at exact bytes, not rerun after Corecache cleanup.',
              'Historical replay controls depend on old cached pair; never rerun their past namespaces after the first new full build overwrites that pair. Their canonical reports remain provenance.',
              'Current fullbuild/2192031621/native originals/mandatoryaudit/root/critic/exact/current optimizedRelease/rawpostcommit/protected backend/fullgoal gates remain open. No phone/globalFD/reference-release/continuousvisibility/totalfilesystem guarantee.'
          ], 'checkedAt': time.time()}
target = B / 'source260-root-preparation-r1.json'; assert not target.exists(); target.write_text(json.dumps(result, indent=2) + '\n'); print(json.dumps(result))
