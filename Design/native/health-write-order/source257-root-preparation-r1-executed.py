"""Verify frozen current/archive bytes, meaningful source controls and shipping projection."""
from pathlib import Path
import ast,base64,gzip,hashlib,json,time
B=Path(__file__).resolve().parent;R=B.parents[2];load=lambda n:json.loads((B/n).read_bytes());sha=lambda x:hashlib.sha256(x).hexdigest()
m=load('durable-source-r257.json');a=json.loads(gzip.decompress((B/'durable-source-r257.json.gz').read_bytes()));old=load('durable-source-r256.json');prior=json.loads(gzip.decompress((B/'durable-source-r256.json.gz').read_bytes()));count=0;changed=[]
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(a[key])
 for name,f in m[group].items():
  p=R/name;assert not p.is_symlink();raw=p.read_bytes();assert raw==(a[key][name].encode() if key=='files' else base64.b64decode(a[key][name],validate=True));assert len(raw)==f['bytes'] and sha(raw)==f['sha256'];count+=1
 for name,f in old[group].items():
  if m[group][name]!=f:changed.append(name)
assert changed==m['priorModified'] and len(changed)==5
# Reuse the reviewed conditional projector, without executing historical source audit.
tree=ast.parse((B/'source254-root-preparation-r2-executed.py').read_bytes());fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='shipping');env={};exec(compile(ast.fix_missing_locations(ast.Module(body=[fn],type_ignores=[])),'reviewed-shipping-projector','exec'),env)
for name in changed:
 if name.startswith('Lumen/'):assert env['shipping'](a['files'][name])==env['shipping'](prior['files'][name]),name
key='LumenUITests/LumenSmokeTests.swift';name='    @MainActor\n    func testHealthBackupFileRecoveryTargetChangedDuringConfirmationNotNowOriginData()'
def method(s):
 start=s.index(name);end=s.index('    @MainActor\n',start+len(name));return s[start:end]
assert method(a['files'][key])==method(prior['files'][key])
for kind in ['uitest','lifecycle']:
 d=load('source257-'+kind+'-sdk-typecheck-r3.json');assert d['exit']==0 and not d['stdout'] and not d['stderr']
 for f in d['sources']:assert {'bytes':f['bytes'],'sha256':f['sha256']}==m['files'][f['file']]
reports=['source257-native-guard-controls-r1.json','source257-expiry-guard-controls-r1.json','source257-expiry-protocol-controls-r1.json','source257-host-caller-controls-r2.json','source257-host-deadline-caller-controls-r1.json','source257-cancellation-regression-controls-r1.json','source257-native-lifecycle-controls-r1.json','source257-finalizer-argument-controls-r1.json','source257-finalizer-caller-controls-r1.json','source257-runner-reference-controls-r1.json']
controls={}
for name in reports:
 d=load(name);assert d['status'].startswith('PASS'),name;controls[name]=dict(status=d['status'],cases=d.get('count',len(d.get('cases',[]))))
 for key in ['sources','inputs']:
  for file,fact in d.get(key,{}).items():
   path=file if file.startswith('Lumen/') else str(B.relative_to(R)/file)
   assert m['files'][path]==fact,(name,file)
 for key in ['source','actualSource']:
  f=d.get(key)
  if isinstance(f,dict) and 'file' in f:assert m['files'][str(B.relative_to(R)/f['file'])]=={k:f[k] for k in ['bytes','sha256']}
 if 'fixture' in d:
  raw=gzip.decompress((B/d['fixture']).read_bytes());assert len(raw)==d['decodedBytes'] and sha(raw)==d['decodedSHA256']
clock=load('source257-native-lifecycle-controls-r1.json');full=json.loads(gzip.decompress((B/clock['fixture']).read_bytes()));assert full['compileExit']==full['runExit']==0
actual=json.loads(full['runStdout']);assert actual['outerElapsedSeconds']>=90 and actual['actualChanges']==0 and actual['answer']=='checked-1'
events=actual['expiredTrace']['events'];assert len(events)==4 and events[2]['reason']=='deadline' and events[3]['expiryElapsedSeconds']>=90 and events[3]['taskCancelled'] is False
assert actual['expiredTrace']['problems']==[] and len(actual['completedTrace']['events'])==5
assert len(actual['finalTrace']['problems'])==1 # Deliberate early Check rejection, fixture-only.
p=load('health-current-release-source257-r1-predeclared-plan.json');previous=load('health-current-release-source255-r1-predeclared-plan.json');new=['-health-legacy-confirmation-expiry-ui','Lumen-confirmation-expiry-verification-v1']
for k in ['checkedDevelopmentMarkers','debugPositiveControls']:assert p[k]==previous[k]+new
for k in ['negativeMarkersWithoutDebugPositive','verifiedProductionMarkers']:assert p[k]==previous[k]
proof=load('source255-release-exact-github.json');assert proof['commit']=='5d6304c0abc52c351115156e0c8ac811ed7168b2' and proof['unionPaths']==2235
result=dict(status='PASS frozen1045/currentarchive, only5expected changes, shipping projection exact, actualSDK typing and isolated expiry/cancellation controls; independent source review pending',source=m['source'],bindings=count,priorModified=changed,priorUnchanged=977-len(changed),appended=count-977,controls=controls,realIsolatedDeadlineSeconds=actual['outerElapsedSeconds'],qualifications='90second control uses actual gate/trace with named Bundle/arguments/container/control/session/fixed-value stubs on macOS. Deliberate early Check rejected and records one problem; later check exercises actual code but is not a problem-free native trial. Caller/schema synthetic expiry metadata expressly no trueclock/native proof. Initial caller R1 failed missing digest comparison, driver fixed and R2/R1deadline controls pass. Native wholealert/currentpair/regression/expiry/Release remain pending.',checkedAt=time.time())
p=B/'source257-root-preparation-r1.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
