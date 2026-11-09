"""Genuine historical file-fact replay and separately labelled command controls."""
from pathlib import Path
import copy, hashlib, importlib.util, json, time
B = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('actual_retained_evidence', B / 'retained-owner-evidence-r1.py')
e = importlib.util.module_from_spec(spec); spec.loader.exec_module(e)
manifest = B / 'durable-source-r257.json'; archive = B / 'durable-source-r257.json.gz'
receipt_path = B / 'health-target-change-source257-r1-build.json'
m = json.loads(manifest.read_bytes()); receipt = json.loads(receipt_path.read_bytes())
app = e.file_fact(e.APP); test = e.file_fact(Path(receipt['testBinary']))
assert app['sha256'] == receipt['sha256'] and app['bytes'] == receipt['binaryBytes']
assert test['sha256'] == receipt['testBinarySHA256'] and test['bytes'] == receipt['testBinaryBytes']
current = {'source': m['source'], 'build': receipt_path.name,
           'inputCount': len(m['files']) + len(m['fixtureInputs']),
           'manifest': e.file_fact(manifest), 'archive': e.file_fact(archive),
           'receipt': e.file_fact(receipt_path), 'app': app, 'test': test}
cases = []
assert e.validate_preflight_replay(copy.deepcopy(current), current)
cases.append({'name': 'genuine historical257 metadata replay', 'accepted': True})


def reject(name, mutate):
    recorded = copy.deepcopy(current); mutate(recorded)
    try: e.validate_preflight_replay(recorded, current); accepted = True
    except (AssertionError, ValueError, TypeError, KeyError): accepted = False
    cases.append({'name': name, 'accepted': accepted, 'recorded': recorded}); assert not accepted, name


for key in ['manifest', 'archive', 'receipt', 'app', 'test']:
    reject(key + ' missing', lambda value, key=key: value.pop(key))
    reject(key + ' null', lambda value, key=key: value.update({key: None}))
    reject(key + ' changed hash', lambda value, key=key: value[key].update(sha256='0' * 64))
    reject(key + ' changed bytes', lambda value, key=key: value[key].update(bytes=value[key]['bytes'] + 1))
    reject(key + ' spoofed path', lambda value, key=key: value[key].update(path='/tmp/spoofed-input'))
    reject(key + ' changed inode', lambda value, key=key: value[key]['identity'].update(st_ino=value[key]['identity']['st_ino'] + 1))
reject('changed source', lambda value: value.update(source='durable-source-r258.json'))
reject('changed build', lambda value: value.update(build='health-target-change-source258-r1-build.json'))
reject('wrong input count', lambda value: value.update(inputCount=value['inputCount'] + 1))
reject('Boolean identity cannot impersonate integer', lambda value: value['receipt']['identity'].update(st_nlink=True))
reject('extra unbound metadata', lambda value: value.update(unbound='ignored?'))
# Command/case validation is a separate synthetic input to the actual checker
# helper. These renamed draft facts do not exist as a current259 build.
draft = copy.deepcopy(current); draft.update(source=e.SOURCE, build=e.BUILD)
draft['manifest']['path'] = str(B / e.SOURCE); draft['archive']['path'] = str(B / (e.SOURCE + '.gz')); draft['receipt']['path'] = str(B / e.BUILD)
raw = Path('/tmp/LumenBatch44Checks'); command_cases = []
for case in ['children', 'pending-back', 'sheet-dismiss']:
    prefix, stem = e.names(case)
    state = {'source': e.SOURCE, 'build': e.BUILD, 'case': case, 'prefix': prefix, 'stem': stem,
             'command': e.command(case, raw), 'preflight': copy.deepcopy(draft)}
    assert e.validate_recorded(state, draft, case, raw)
    command_cases.append({'case': case, 'name': 'synthetic command/case positive', 'accepted': True})
    for field, replacement in [('-destination', 'platform=iOS Simulator,id=OTHER'),
                               ('-resultBundlePath', '/tmp/wrong.xcresult')]:
        changed = copy.deepcopy(state); index = changed['command'].index(field); changed['command'][index + 1] = replacement
        try: e.validate_recorded(changed, draft, case, raw); accepted = True
        except AssertionError: accepted = False
        assert not accepted; command_cases.append({'case': case, 'name': field + ' tamper', 'accepted': accepted})
    for change in ['other-only-test', 'duplicate-destination', 'drop-without-building', 'wrong-build', 'null-preflight']:
        changed = copy.deepcopy(state)
        if change == 'other-only-test': changed['command'][-4] = '-only-testing:LumenUITests/LumenSmokeTests/OTHER'
        elif change == 'duplicate-destination': changed['command'] += ['-destination', 'id=OTHER']
        elif change == 'drop-without-building': changed['command'][-1] = 'test'
        elif change == 'wrong-build': changed['build'] = 'other.json'
        else: changed['preflight'] = None
        try: e.validate_recorded(changed, draft, case, raw); accepted = True
        except (AssertionError, TypeError): accepted = False
        assert not accepted; command_cases.append({'case': case, 'name': change, 'accepted': accepted})
report = {'status': 'PASS actual file-fact replay and separate command tamper controls',
          'historicalGenuineMetadata': current, 'metadataCases': cases, 'metadataCount': len(cases),
          'commandCases': command_cases, 'commandCount': len(command_cases),
          'source': {'file': 'retained-owner-evidence-r1.py', 'bytes': (B / 'retained-owner-evidence-r1.py').stat().st_size,
                     'sha256': hashlib.sha256((B / 'retained-owner-evidence-r1.py').read_bytes()).hexdigest()},
          'scope': 'Actual generic replay helper receives genuine retained257 manifest/archive/receipt and freshly read matching historical257 app/test cache identities. No old257 source-bound audit executed or current257 source validity claimed. Separately synthetic renamed259 command/case facts exercise exact argv validation only; no259fullbuild/preflight/native/checker-main acceptance. Actual259 preflight must independently verify all current source and current receipt/pair.',
          'checkedAt': time.time()}
target = B / 'source259-retained-metadata-controls-r2.json'; assert not target.exists(); target.write_text(json.dumps(report, indent=2) + '\n')
print(report['status'], report['metadataCount'], report['commandCount'])
