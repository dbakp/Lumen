"""Independent root binding of retained R5 endpoints; no simulator actions."""
import base64, gzip, hashlib, json, subprocess, time
from pathlib import Path
B = Path(__file__).resolve().parent
REPO = B.parents[2]
def digest(raw): return hashlib.sha256(raw).hexdigest()
def load(name): return json.loads((B/name).read_bytes())
def fact(name):
    raw=(B/name).read_bytes()
    return {'file':name,'bytes':len(raw),'sha256':digest(raw)}
name='health-legacy-target-change-data-source230r1-r5-source231r1-outcome.json'
r=load(name); case=load('health-legacy-target-change-data-source230r1-host-audit.json')
assert r['checkerExit']==r['actualNativeExit']==r['actualDriverExit']==0
assert r['actualNativeCounts']==[1,0,0] and r['retainedValidationComplete']
assert r['checkerSource']=='durable-source-r231.json' and r['caseSource']=='durable-source-r230.json'
bindings=0
for source in ['durable-source-r231.json','durable-source-r230.json']:
    manifest=load(source); archive=json.loads(gzip.decompress((B/(source+'.gz')).read_bytes()))
    for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
        assert set(manifest[group])==set(archive[key])
        for path,wanted in manifest[group].items():
            raw=(REPO/path).read_bytes()
            saved=archive[key][path].encode() if key=='files' else base64.b64decode(archive[key][path],validate=True)
            assert raw==saved and len(raw)==wanted['bytes'] and digest(raw)==wanted['sha256']
            bindings+=1
payloads=0
def decode_tree(value):
    global payloads
    if isinstance(value,dict):
        if isinstance(value.get('base64'),str):
            raw=base64.b64decode(value['base64'],validate=True)
            assert len(raw)==value['bytes'] and digest(raw)==value['sha256']
            payloads+=1
        for item in value.values(): decode_tree(item)
    elif isinstance(value,list):
        for item in value: decode_tree(item)
decode_tree(r)
a=r['finalAudit']; assert a['mode']=='absent' and len(a['samples'])==2
first=case['boundaries'][0]; last=case['boundaries'][-1]
for sample in a['samples']:
    p=sample['process']
    assert p['exit']==0 and p['parseComplete'] and p['matches']==[] and p['mode']=='absent'
    assert p['command']==['/bin/ps','-axo','pid=,comm='] and p['expectedPID']==case['appPID']
    assert p['stdoutBytes']>0 and p['parsedRows']>0
    assert sample['installed']==first['installed']==r['installedBeforeAudit']
    assert sample['protected']==first['protected']
    assert len(sample['protected']['current']['files'])==len(sample['protected']['prior']['files'])==13
    assert sample['fixed']['fixed']==last['endpoints'][-1]['fixed']['fixed']
    assert sample['fixed']['classification']=='new' and not sample['fixed']['healthConnected']
    fixed=sample['fixed']['fixed']
    assert fixed['lumen.health.meals.v1']['bytes']==40
    assert fixed['lumen.health.meals.v1']['sha256']=='a352b024bfe51c5b74e3effef11dc1f6855458a3c473c2a343044588ede593ba'
    assert fixed['lumen.health.workouts.v1']['bytes']==42
    assert json.loads(base64.b64decode(sample['nativeState']['base64']))==last['observation']
    assert sample['originEvents']==last['originEvents']
    assert sample['owned']=={} and len(sample['caseRoots'])==4 and not any(sample['caseRoots'].values())
    assert 'liveOpenPaths' not in sample
span=a['samples'][1]['monotonic']-a['samples'][0]['monotonic']; assert span>=.25
originals=['health-legacy-target-change-data-source230r1-live-audit.json','source230-r4-checker-actual-outcome.json']
for original in originals:
    raw=(B/original).read_bytes()
    backed=subprocess.check_output(['git','show','22b64eb4211f133bab92726446f34ed8e73f1bf4:Design/native/health-write-order/'+original],cwd=REPO)
    assert raw==backed
result={'status':'PASS root actual R5 retained bindings; independent Part120 still required',
 'outcome':fact(name),'sourceBindings':bindings,'decodedR5PayloadInstances':payloads,
 'mode':'absent','sampleCount':2,'sampleStartSpanSeconds':span,'protectedFilesPerSample':26,
 'nativeCounts':[1,0,0],'newNativeRuns':0,'newAppBuilds':0,
 'originalR4FailureUnchanged':list(map(fact,originals)),
 'scope':'Two successful full process enumerations and exact protected/newer/provider/installed/native-final/empty-owner/four-absent-case-root endpoints. No live-app lsof, continuous absence, precise flush latency, fresh raw-token commit, Release or full-product credit.',
 'checkedAt':time.time()}
target=B/'source231-root-actual-r5-review-r1.json'; assert not target.exists()
target.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
