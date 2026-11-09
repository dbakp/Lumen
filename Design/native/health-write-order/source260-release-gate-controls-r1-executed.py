"""Exercise actual prerequisite gate in an isolated tiny synthetic Git repository."""
from pathlib import Path
import copy, hashlib, importlib.util, json, subprocess, tempfile, time
B = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('gate', B/'source260-native-release-gate-r1.py')
gate = importlib.util.module_from_spec(spec); spec.loader.exec_module(gate)
output = B/'source260-release-gate-controls-r1.json'
assert not output.exists()
results = []
with tempfile.TemporaryDirectory(prefix='lumen260-release-gate-') as temporary:
    repo = Path(temporary); base = repo/'evidence'; base.mkdir()
    def git(*args):
        return subprocess.check_output(['git',*args],cwd=repo,stderr=subprocess.PIPE,text=True).strip()
    git('init','-q'); git('config','user.name','Synthetic gate control'); git('config','user.email','synthetic@example.invalid')
    names = ['health-retained-review-owner-source260-round2-part184-sheet-dismiss-native.json','source260-root-part184-review.json']
    values = {'source':'durable-source-r260.json','case':'sheet-dismiss','part':184,'scopedNativeAcceptance':True,'globalProductAcceptance':False,'requiredCorrectionsForThisScopedCase':[]}
    for name in names: (base/name).write_text(json.dumps(values))
    git('add','evidence'); git('commit','-qm','Synthetic only'); commit=git('rev-parse','HEAD');git('update-ref','refs/remotes/origin/main',commit)
    proof={'source':values['source'],'commit':commit,'proofs':[{'file':'evidence/'+name,'bytes':len((raw:=(base/name).read_bytes())),'sha256':hashlib.sha256(raw).hexdigest()} for name in names]}
    gate.require_native_checkpoint(base,repo,proof);results.append({'case':'exact synthetic checkpoint','accepted':True})
    def reject(label, candidate):
        try: gate.require_native_checkpoint(base,repo,candidate)
        except (AssertionError,KeyError,subprocess.CalledProcessError): results.append({'case':label,'rejected':True})
        else: raise AssertionError(label+' unexpectedly accepted')
    for label, mutate in [
        ('wrong proof source',lambda p:p.update(source='durable-source-r259.json')),
        ('wrong proof commit',lambda p:p.update(commit='0'*40)),
        ('missing exact report row',lambda p:p['proofs'].pop(0)),
        ('duplicate exact report row',lambda p:p['proofs'].append(copy.deepcopy(p['proofs'][0]))),
        ('Boolean byte alias',lambda p:p['proofs'][0].update(bytes=True)),
        ('wrong SHA',lambda p:p['proofs'][0].update(sha256='0'*64)),
    ]:
        candidate=copy.deepcopy(proof);mutate(candidate);reject(label,candidate)
    git('update-ref','refs/remotes/origin/main','0'*40);reject('missing origin main',proof);git('update-ref','refs/remotes/origin/main',commit)
    original=(base/names[0]).read_bytes();(base/names[0]).write_bytes(original+b' ');reject('local report tamper',proof)
    candidate=copy.deepcopy(proof);raw=(base/names[0]).read_bytes();candidate['proofs'][0].update(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest());reject('local plus proof row tamper versus Git',candidate);(base/names[0]).write_bytes(original)
    # Commit structurally invalid scoped reports to test semantic checks after real Git binding.
    for field,value in [('scopedNativeAcceptance',1),('case','children'),('part',True),('requiredCorrectionsForThisScopedCase',['required correction'])]:
        changed=copy.deepcopy(values);changed[field]=value;(base/names[0]).write_text(json.dumps(changed));git('add','evidence');git('commit','-qm','Synthetic invalid report')
        candidate=copy.deepcopy(proof);candidate['commit']=git('rev-parse','HEAD');git('update-ref','refs/remotes/origin/main',candidate['commit']);raw=(base/names[0]).read_bytes();candidate['proofs'][0].update(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest());reject('actual committed invalid '+field,candidate)
raw=(B/'source260-native-release-gate-r1.py').read_bytes()
result={'status':'PASS actual gate isolated synthetic Git positive and negatives','source':'durable-source-r260.json','helperBytes':len(raw),'helperSHA256':hashlib.sha256(raw).hexdigest(),'cases':results,'scope':'Actual gate function with real tiny temporary synthetic Git blobs/local files. No actual184 existence, native success, current release execution or global product acceptance. Temporary synthetic repository removed.','checkedAt':time.time()}
output.write_text(json.dumps(result,indent=2)+'\n');print(len(results),'isolated gate controls passed')
