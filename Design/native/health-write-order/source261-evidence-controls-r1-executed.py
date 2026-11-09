"""Pure synthetic receipt/command controls and actual tiny local Git blob anchors.

Not a Source261 build, frozen source or GitHub publication proof. Exclusive outputs.
"""
from pathlib import Path
import copy
import hashlib
import importlib.util
import json
import subprocess
import tempfile
import time

B = Path(__file__).resolve().parent
output = B / 'source261-evidence-controls-r1.json'; assert not output.exists()
helper = B / 'retained-backend-evidence-r1.py'; original = helper.read_bytes()
spec = importlib.util.spec_from_file_location('evidence', helper)
e = importlib.util.module_from_spec(spec); spec.loader.exec_module(e)
manifest = {'source': e.SOURCE, 'files': {'LumenUITests/LumenSmokeTests.swift': {'sha256':'a'*64}}, 'fixtureInputs': {}}
receipt = {'source':e.SOURCE, 'buildExit':0, 'sourceInputs':1, 'fixtureInputs':0,
           'binaryBytes':10, 'testBinaryBytes':10, 'appCarrySource':'durable-source-r260.json',
           'testBuiltSource':e.SOURCE, 'appCarriedUnchanged':True, 'testSourceSHA256':'a'*64}
checks = []
assert e.validate_receipt(receipt, manifest, e.SOURCE)
checks.append({'case':'synthetic typed receipt accepted; no actual build receipt inferred', 'accepted':True})
for key, wrong in [('source','durable-source-r260.json'), ('buildExit',1), ('buildExit',False),
                   ('sourceInputs',True), ('sourceInputs',2), ('fixtureInputs',False),
                   ('binaryBytes',True), ('testBinaryBytes',0),
                   ('appCarrySource','durable-source-r259.json'), ('testBuiltSource','durable-source-r260.json'),
                   ('appCarriedUnchanged',1), ('appCarriedUnchanged',False), ('testSourceSHA256','b'*64)]:
    value = dict(receipt); value[key] = wrong
    try: e.validate_receipt(value, manifest, e.SOURCE)
    except (AssertionError, KeyError, ValueError, TypeError): pass
    else: raise AssertionError(('invalid receipt accepted', key, wrong))
    checks.append({'case':'synthetic receipt rejects ' + key, 'wrongValue':wrong, 'accepted':False})
command = e.command('retained-meals-backend', Path('/synthetic-only-results'))
assert command[command.index('-destination')+1] == 'platform=iOS Simulator,id=' + e.DEVICE
assert command[-1] == 'test-without-building'
assert [v for v in command if v.startswith('-only-testing:')] == ['-only-testing:LumenUITests/LumenSmokeTests/testHealthRetainedReviewOwnerBackend']
assert command[command.index('-parallel-testing-enabled')+1] == 'NO'
checks.append({'case':'command is exact approved simulator and dedicated backend method; no execution', 'command':command})
for function in (e.names, e.proof_name):
    try: function('other-case')
    except AssertionError: pass
    else: raise AssertionError('other native namespace accepted')
checks.append({'case':'other native case rejected by names and proof mapping', 'accepted':False})
with tempfile.TemporaryDirectory(prefix='lumen261-evidence-control-') as temporary:
    root = Path(temporary).resolve()
    def git(*args): return subprocess.check_output(['git',*args],cwd=root,stderr=subprocess.STDOUT).decode().strip()
    git('init','-q'); git('config','user.name','Lumen synthetic control'); git('config','user.email','lumen-control@example.invalid')
    facts = {'source':e.SOURCE}; rows = []
    for key in ('manifest','archive','receipt'):
        path = root / (key + '.synthetic'); data = ('synthetic-' + key).encode(); path.write_bytes(data)
        facts[key] = {'path':str(path),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
        rows.append({'file':path.name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
    git('add','.'); git('commit','-qm','Synthetic control only')
    proof = {'source':e.SOURCE,'commit':git('rev-parse','HEAD'),'proofs':rows}
    assert e.verify_checkpoint_facts(proof,facts,root)
    checks.append({'case':'actual tiny local Git selected blobs match synthetic metadata', 'accepted':True})
    wrong = copy.deepcopy(proof); changed = copy.deepcopy(facts)
    wrong['proofs'][0]['sha256'] = 'f'*64; changed['manifest']['sha256'] = 'f'*64
    try: e.verify_checkpoint_facts(wrong,changed,root)
    except AssertionError: pass
    else: raise AssertionError('coherently edited proof and facts accepted without Git bytes')
    checks.append({'case':'coherently edited local proof and facts fail actual Git blob anchor', 'accepted':False})
    wrong = copy.deepcopy(proof); wrong['proofs'].append(copy.deepcopy(wrong['proofs'][0]))
    try: e.verify_checkpoint_facts(wrong,facts,root)
    except AssertionError: pass
    else: raise AssertionError('duplicate proof row accepted')
    checks.append({'case':'duplicate proof row rejected', 'accepted':False})
    wrong = copy.deepcopy(facts); wrong['archive']['bytes'] = True
    try: e.verify_checkpoint_facts(proof,wrong,root)
    except AssertionError: pass
    else: raise AssertionError('Boolean file size accepted')
    checks.append({'case':'Boolean file-size alias rejected', 'accepted':False})
assert helper.read_bytes() == original
report = {'status':'PASS synthetic evidence receipt/command and local Git anchor controls',
          'helperBytes':len(original),'helperSHA256':hashlib.sha256(original).hexdigest(),
          'sourceBeforeAfterExact':True,'checkCount':len(checks),'checks':checks,
          'temporarySyntheticRepositoryRemoved':True,
          'scope':'Pure synthetic receipt/command and actual tiny local Git fixture only. No source261 freeze, actual build, simulator, GitHub proof or backend acceptance.',
          'remaining':'Actual new build/current app-test receipt and full source/proof/controller/checker integration remain pending.',
          'checkedAt':time.time()}
output.write_text(json.dumps(report,indent=2)+'\n')
print(len(checks),'evidence controls passed; no build or simulator action')
