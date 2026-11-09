"""Verify current frozen source and exact scoped preparation controls."""
from pathlib import Path
import base64, gzip, hashlib, json, tempfile, time
B = Path(__file__).resolve().parent; R = B.parents[2]
load = lambda name: json.loads((B / name).read_bytes())
sha = lambda raw: hashlib.sha256(raw).hexdigest()
m = load('durable-source-r258.json'); old = load('durable-source-r257.json')
a = json.loads(gzip.decompress((B / 'durable-source-r258.json.gz').read_bytes()))
count = 0
for group, key in [('files', 'files'), ('fixtureInputs', 'binaryFiles')]:
    assert set(m[group]) == set(a[key])
    for name, fact in m[group].items():
        file = R / name; assert not file.is_symlink(); raw = file.read_bytes()
        assert len(raw) == fact['bytes'] and sha(raw) == fact['sha256'], name
        assert raw == (a[key][name].encode() if key == 'files' else base64.b64decode(a[key][name], validate=True))
        count += 1
changed = [name for group in ['files', 'fixtureInputs'] for name in old[group] if old[group][name] != m[group][name]]
assert changed == m['priorModified']
controls = {}
for name, expected in [('source258-retained-owner-core-r5.json', 35),
                       ('source258-retained-guard-controls-r2.json', 10),
                       ('source258-retained-protocol-controls-r2.json', 34),
                       ('source258-runner-argument-controls-r2.json', 13)]:
    d = load(name); assert d['status'].startswith('PASS')
    actual = d.get('count', len(d.get('checks', []))); assert actual == expected
    if 'checks' in d: assert all(row['passed'] is True for row in d['checks'])
    controls[name] = actual
    fact = d.get('source')
    if isinstance(fact, dict):
        path = fact['file'] if fact['file'].startswith('Lumen/') else str(B.relative_to(R) / fact['file'])
        assert m['files'][path] == {key: fact[key] for key in ['bytes', 'sha256']}
    for file, fact in d.get('sources', {}).items():
        assert m['files'][str(B.relative_to(R) / file)] == fact
full = load('source258-full-core-r3.json'); assert full['passLines'] == 2212 and full['status'].startswith('PASS')
raw = gzip.decompress((B / 'source258-full-core-r3.log.gz').read_bytes())
assert len(raw) == full['logBytes'] and sha(raw) == full['logSHA256']
assert sum(line.startswith('PASS:') for line in raw.decode().splitlines()) == 2212
for name, fact in full['sources'].items(): assert m['files'][name] == fact
sdk = {}
for kind in ['whole-app', 'uitest']:
    d = load('source258-' + kind + '-sdk-r4.json')
    assert d['status'] == 'PASS' and d['exit'] == 0 and d['sourceFenceExact'] is True
    assert d['sourcesBefore'] == d['sourcesAfter']
    generated = []
    for name, fact in d['sourcesBefore'].items():
        if name.startswith('/tmp/'):
            assert name.endswith('/GeneratedAssetSymbols.swift'); generated.append({'file': name, **fact})
        else: assert m['files'][name] == fact, name
    assert len(d['sourcesBefore']) == (196 if kind == 'whole-app' else 1)
    if kind == 'whole-app': assert len(generated) == 1
    sdk[kind] = {'sourceCount': len(d['sourcesBefore']), 'generated': generated, 'diagnosticBytes': len(d['stderr'].encode())}
plan = load('health-current-release-source258-r1-predeclared-plan.json')
prior = load('health-current-release-source257-r1-predeclared-plan.json')
markers = ['-health-retained-review-owner-ui', 'Lumen-retained-review-owner-v1']
for key in ['checkedDevelopmentMarkers', 'debugPositiveControls']: assert plan[key] == prior[key] + markers
for key in ['negativeMarkersWithoutDebugPositive', 'verifiedProductionMarkers']: assert plan[key] == prior[key]
assert [len(plan[key]) for key in ['checkedDevelopmentMarkers', 'debugPositiveControls', 'negativeMarkersWithoutDebugPositive', 'verifiedProductionMarkers']] == [219, 203, 16, 21]
proof = load('source257-release-exact-github-r2.json'); assert proof['commit'] == '5701c734fee2e101d04e3f978a752865eda1159c' and proof['unionPaths'] == 2411
leftovers = [str(p) for p in Path(tempfile.gettempdir()).glob('Lumen-retained-owner-*')]
assert not leftovers, leftovers
result = {'status': 'PASS frozen current/archive and scoped controls; independent source review pending',
          'source': m['source'], 'bindings': count, 'priorModified': changed, 'controls': controls,
          'fullCorePassLines': 2212, 'sdk': sdk, 'taskOwnedCoreFixtureRootsAtCheck': leftovers,
          'qualifications': [
              'Production retained owner, origin binding and Settings lifetime intentionally change; no unchanged-shipping projection claimed.',
              'Core35 and full2212 are pure logic, without LocalStore locking or SwiftUI/native runtime. Native cases, full current build/test pair/current markers/Release remain required.',
              'Guard10 extracts actual context property only; protocol34 uses synthetic traces; runner13 covers actual help/rejection/pure command builder only, not actual main failure retention.',
              'SDK R4 whole196 includes195 current frozen app files plus one actual generated asset-symbol source; no stubs. Existing concurrency warnings retained, not resolved.',
              'Earlier core/SDK/protocol reports remain historical preparation. R1/R2 compiler/fixture failures and SDK pre-fence qualification retained. R5 fixtureRootRemovedOnReturn expresses scheduled defer; independent current task-prefix absence check is the actual cleanup observation.',
              'Original native acquisitions and visual review have not occurred. No sourceReady/runtime/full-goal acceptance until same critic reviews this checkpoint.'
          ], 'checkedAt': time.time()}
target = B / 'source258-root-preparation-r1.json'; assert not target.exists(); target.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
