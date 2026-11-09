"""Independent current case source/pair/raw export/query provenance readback."""
from pathlib import Path
import base64, gzip, hashlib, importlib.util, json, time
B = Path(__file__).resolve().parent
prefix = 'retained-owner-source260-children-r1'
load = lambda name: json.loads((B / name).read_bytes())
sha = lambda raw: hashlib.sha256(raw).hexdigest()
spec = importlib.util.spec_from_file_location('current_retained_driver', B / 'retained-owner-driver-r3.py')
d = importlib.util.module_from_spec(spec); spec.loader.exec_module(d)
state = load(prefix + '-driver.json'); audit = load(prefix + '-mandatory-audit.json')
query = load(prefix + '-mandatory-checker-query.json'); final = load(prefix + '-finalization.json')
assert state['status'] == 'NATIVE_FINISHED acceptance pending' and state['nativeExit'] == 0 and state['errors'] == []
assert state['originalFailures'] == [] and audit['status'].startswith('SUPPORTED') and final['status'].startswith('SUPPORTED')
assert type(query['pid']) is int and query['pid'] > 0 and type(query['exit']) is int and query['exit'] == 0
assert final['actualCheckerQuery'] == query
for stream in ['stdout', 'stderr']: base64.b64decode(query[stream], validate=True)
summary = json.loads(base64.b64decode(state['summaryQuery']['stdout'], validate=True))
assert [summary[key] for key in ['passedTests', 'failedTests', 'skippedTests']] == [1, 0, 0]
e = d.module('retained-owner-evidence-r2.py'); p = d.module('retained-owner-protocol-r1.py')
current = e.preflight(B, e.SOURCE, d.verify_source)
assert e.validate_recorded(state, current, 'children', d.RAW)
assert e.validate_preflight_replay(state['preflightAfter'], current)
assert e.strict_json_equal(audit['currentExecutionFacts'], current)
proof = load(state['prerequisiteExactProof']); assert e.verify_checkpoint_facts(proof, current, d.R)
assert e.strict_json_equal(state['providerBefore'], state['providerAfter']) and e.strict_json_equal(state['providerAfter'], d.provider())
raw_dir = d.RAW / (state['stem'] + 'All'); assert not raw_dir.is_symlink()
raw_names = {path.name for path in raw_dir.iterdir()}; assert raw_names == {row['name'] for row in state['originals']}
assert len(state['originals']) == 11
verified = []
for row in state['originals']:
    assert Path(row['file']).name == row['file'] and Path(row['name']).name == row['name']
    canonical, acquired = B / row['file'], raw_dir / row['name']
    assert not canonical.is_symlink() and not acquired.is_symlink()
    raw = canonical.read_bytes(); assert raw == acquired.read_bytes()
    assert len(raw) == row['bytes'] and sha(raw) == row['sha256']
    verified.append({key: row[key] for key in ['file', 'name', 'bytes', 'sha256']})
manifest = load(state['originalManifest']); assert len(manifest) == 1
attachments = manifest[0]['attachments']; readback_item = next(row for row in attachments if row['exportedFileName'].endswith('.json'))
readback_name = next(row['file'] for row in state['originals'] if row['name'] == readback_item['exportedFileName'])
readback = load(readback_name); trace = load(state['trace']['file'])
assert p.validate('children', trace, readback) == audit['protocol']
for fact, zipped in [(state['log'], True), (state['trace'], False)]:
    raw = (B / fact['file']).read_bytes(); raw = gzip.decompress(raw) if zipped else raw
    assert len(raw) == fact['bytes'] and sha(raw) == fact['sha256']
bindings = []
for name in [prefix + '-driver.json', prefix + '-mandatory-audit.json', prefix + '-mandatory-checker-query.json',
             prefix + '-finalization.json', state['trace']['file'], state['log']['file'],
             'health-target-change-source260-r1-build.json', 'source260-build-exact-github.json']:
    raw = (B / name).read_bytes(); bindings.append({'file': name, 'bytes': len(raw), 'sha256': sha(raw)})
result = {'status': 'SUPPORTED actual children navigation/trace/readback/native recovery banner; independent visual critic pending',
          'source': e.SOURCE, 'sourceInputs': current['inputCount'], 'nativePID': state['nativePID'], 'nativeExit': state['nativeExit'],
          'passedFailedSkipped': [1, 0, 0], 'mandatoryCheckerPID': query['pid'], 'mandatoryCheckerExit': query['exit'],
          'protocol': audit['protocol'], 'rawCanonicalOriginals': verified, 'supportBindings': bindings,
          'rootMethod': 'All11 raw unfiltered originals compared to canonical bytes/hash; full native helper/summary/trace/query/finalization read; fresh current1162 source/pair/proof/provider facts checked, no native rerun.',
          'scope': 'Same ready review/capture/selected meal persists through actual records/photo and return; real Notnow, Back/old close, fresh distinct owner/capture/off selection, native recovery success banner, final Back/close. Not raw postcommit/receipt/journal/protected-file backend, wholeForm/contrast/appearance/speech/motion/globalFD/reference-release/continuousabsence/Release/fullgoal acceptance.',
          'checkedAt': time.time()}
target = B / 'source260-children-root-native-r1.json'; assert not target.exists(); target.write_text(json.dumps(result, indent=2) + '\n'); print(result['status'])
