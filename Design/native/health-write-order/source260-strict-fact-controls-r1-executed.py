"""Actual shared type, receipt and Git-anchored historical metadata controls."""
from pathlib import Path
import copy, hashlib, importlib.util, json, math, time
B = Path(__file__).resolve().parent; R = B.parents[2]
spec = importlib.util.spec_from_file_location('retained_evidence_r2', B / 'retained-owner-evidence-r2.py')
e = importlib.util.module_from_spec(spec); spec.loader.exec_module(e)
checks = []
for name, left, right, expected in [
    ('same integers', 1, 1, True), ('Boolean/int', True, 1, False), ('float/int', 1.0, 1, False),
    ('same float', 1.0, 1.0, True), ('signed float zero', -0.0, 0.0, False), ('nested Boolean', {'a': [True]}, {'a': [1]}, False),
    ('null', None, None, True), ('null/string', None, 'null', False), ('tuple/list', (1,), [1], False),
    ('invalid numeric keys', {1: 'a'}, {1: 'a'}, False), ('NaN', math.nan, math.nan, False),
    ('infinity', math.inf, math.inf, False), ('UTF units differ', 'e\u0301', 'é', False)]:
    observed = e.strict_json_equal(left, right); assert observed is expected
    checks.append({'name': name, 'accepted': observed})
for value, minimum, expected in [(0, 0, True), (0, 1, False), (1, 1, True), (True, 0, False), (False, 0, False),
                                 (1.0, 0, False), (0.0, 0, False), (-1, 0, False), ('1', 0, False), (None, 0, False)]:
    try: e.require_int(value, minimum); accepted = True
    except AssertionError: accepted = False
    assert accepted is expected; checks.append({'name': 'integer rule', 'value': value, 'minimum': minimum, 'accepted': accepted})
receipt = json.loads((B / 'health-target-change-source257-r1-build.json').read_bytes())
manifest = json.loads((B / 'durable-source-r257.json').read_bytes())
assert e.validate_receipt(receipt, manifest, manifest['source'])
checks.append({'name': 'genuine historical257 receipt schema', 'accepted': True})
for key in ['buildExit', 'sourceInputs', 'fixtureInputs', 'binaryBytes', 'testBinaryBytes']:
    for value in [float(receipt[key]), bool(receipt[key]), None, str(receipt[key])]:
        changed = copy.deepcopy(receipt); changed[key] = value
        try: e.validate_receipt(changed, manifest, manifest['source']); accepted = True
        except (AssertionError, TypeError): accepted = False
        assert not accepted; checks.append({'name': key + ' type', 'value': value, 'accepted': accepted})
facts = json.loads((B / 'source259-retained-metadata-controls-r2.json').read_bytes())['historicalGenuineMetadata']
proof = json.loads((B / 'source257-release-exact-github-r2.json').read_bytes())
assert e.verify_checkpoint_facts(proof, facts, R)
checks.append({'name': 'genuine historical257 three-file Git blob anchor', 'accepted': True})
for key in ['manifest', 'archive', 'receipt']:
    for field in ['sha256', 'bytes']:
        changed = copy.deepcopy(facts)
        changed[key][field] = '0' * 64 if field == 'sha256' else float(changed[key][field])
        try: e.verify_checkpoint_facts(proof, changed, R); accepted = True
        except AssertionError: accepted = False
        assert not accepted; checks.append({'name': key + ' proof-' + field + ' tamper', 'accepted': accepted})
    changed = copy.deepcopy(facts); forged = copy.deepcopy(proof)
    changed[key]['sha256'] = '0' * 64
    name = str(Path(changed[key]['path']).relative_to(R))
    next(row for row in forged['proofs'] if row['file'] == name)['sha256'] = '0' * 64
    try: e.verify_checkpoint_facts(forged, changed, R); accepted = True
    except AssertionError: accepted = False
    assert not accepted; checks.append({'name': key + ' simultaneously forged proof+fact rejected against Git blob', 'accepted': accepted})
report = {'status': 'PASS actual strict JSON/integer/receipt/Git-fact controls', 'count': len(checks), 'cases': checks,
          'source': {'file': 'retained-owner-evidence-r2.py', 'bytes': (B / 'retained-owner-evidence-r2.py').stat().st_size,
                     'sha256': hashlib.sha256((B / 'retained-owner-evidence-r2.py').read_bytes()).hexdigest()},
          'scope': 'Actual helper functions, genuine historical257 receipt/manifest/file metadata and three actual retained Git blobs. Generic schema/integrity fixtures only; no old257 source-bound native audit or current257/260pair/source/runtime acceptance. Empty diagnostics require strict int0; app/test/log/trace use positive sizes.', 'checkedAt': time.time()}
target = B / 'source260-strict-fact-controls-r1.json'; assert not target.exists(); target.write_text(json.dumps(report, indent=2) + '\n')
print(report['status'], report['count'])
