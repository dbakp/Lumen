"""Root read-only retained replay; no reset, acknowledgement, or fixture writes."""
from pathlib import Path
import base64,gzip,hashlib,json,subprocess,time,importlib.util,struct
B=Path(__file__).resolve().parent; R=B.parents[2]; P='health-mixed-ineligible-source245r1'
sha=lambda x:hashlib.sha256(x).hexdigest()
load=lambda n:json.loads((B/n).read_bytes())
spec=importlib.util.spec_from_file_location('mixed_root',B/'health-mixed-ineligible-evidence-r2.py');h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
host=h.verify_host_source('durable-source-r245.json');case=h.verify_inputs('durable-source-r244.json','health-target-change-source244-r1-build.json')
r=load(P+'-host-audit.json'); count=0
def payloads(x):
 global count
 if isinstance(x,dict):
  if {'bytes','sha256','base64'}<=x.keys() and x['base64'] is not None:
   d=base64.b64decode(x['base64'],validate=True);assert len(d)==x['bytes'] and sha(d)==x['sha256'];count+=1
  for v in x.values():payloads(v)
 elif isinstance(x,list):
  for v in x:payloads(v)
payloads(r)
originals=load(P+'-all-originals.json');assert originals['count']==15 and originals['kinds']=={'json':1,'png':14} and originals['driverExit'] is None
for row in originals['rows']:
 d=(B/row['retained']).read_bytes();assert len(d)==row['bytes'] and sha(d)==row['sha256'];assert d==(Path('/tmp/LumenBatch44Checks/HealthMixedIneligibleSource245R1All')/row['file']).read_bytes()
 if row['kind']=='png':assert struct.unpack('>II',d[16:24])==(1206,2622)
assert len(r['before'])==len(r['previous'])==10 and len(r['after'])==18
assert r['released']['intentionallyHostReleased'] is True
assert r['success']['receipt']['domains']==['workouts'] and r['success']['receipt']['omittedPhotoCount']==0
assert r['parent']['rootsAbsent'] and r['relaunchParent']['rootsAbsent']
assert r['selection']['source']['owner']['pid']!=r['relaunchSelection']['source']['owner']['pid']
execution=load('source245-mixed-r1-checker-execution.json');assert execution['checkerExit']==0
for v in execution['streams'].values():
 d=gzip.decompress((B/v['retained']).read_bytes());assert len(d)==v['bytes'] and sha(d)==v['sha256']
# Execute existing strict current-live checker unchanged, with a unique root audit output.
cmd=['python3','-B',str(B/'check-mixed-ineligible-evidence-r2.py'),P,'source245-root-mixed-live-check-r1.json','--host-source','durable-source-r245.json']
run=subprocess.run(cmd,capture_output=True);(B/'source245-root-mixed-live-check-r1-stdout.gz').write_bytes(gzip.compress(run.stdout,mtime=0));(B/'source245-root-mixed-live-check-r1-stderr.gz').write_bytes(gzip.compress(run.stderr,mtime=0))
assert run.returncode==0,run.stderr.decode()
report=load('health-mixed-ineligible-source245-round2-part152-native.json'); bindings=[]
for row in report['provenance']+report['identity']['actualPair']:
 p=Path(row['file']);p=p if p.is_absolute() else R/p;d=p.read_bytes();assert len(d)==row['bytes'] and sha(d)==row['sha256'],str(p)
 if 'decodedBytes' in row:
  raw=gzip.decompress(d);assert len(raw)==row['decodedBytes'] and sha(raw)==row['decodedSHA256']
 bindings.append({k:row[k] for k in ['file','bytes','sha256']})
for row in report['visualReview']:
 d=(B/row['file']).read_bytes();assert len(d)==row['bytes'] and sha(d)==row['sha256'];bindings.append({'file':str((B/row['file']).relative_to(R)),'bytes':len(d),'sha256':sha(d)})
assert len(bindings)==60
out={'status':'PASS root current715host/708compiled/pair/157payloads/15originals/strict unchanged live checker and full152bindings','hostBindings':host['bindings'],'caseInputs':case['inputs'],'hostPayloadInstances':count,'originals':15,'liveCheckerExit':run.returncode,'command':cmd,'part152Bindings':bindings,'scope':'One mixed workouts-only case; existing checker replay plus root retained checks, no fullgoal/timing/VO/motion acceptance. Full152 report read separately.','checkedAt':time.time()}
assert count==157
(B/'source245-root-native-final-audit-r1.json').write_text(json.dumps(out,indent=2)+'\n');print(out['status'])
