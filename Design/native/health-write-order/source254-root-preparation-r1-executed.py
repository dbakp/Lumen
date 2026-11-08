"""Root exact current/archive, shipping projection, native acquisition and producer checks."""
from pathlib import Path
import base64,gzip,hashlib,json,time
B=Path(__file__).resolve().parent;R=B.parents[2];load=lambda n:json.loads((B/n).read_bytes());sha=lambda x:hashlib.sha256(x).hexdigest()
m=load('durable-source-r254.json');a=json.loads(gzip.decompress((B/'durable-source-r254.json.gz').read_bytes()));old=load('durable-source-r253.json');prior=json.loads(gzip.decompress((B/'durable-source-r253.json.gz').read_bytes()));count=0;changed=[]
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(a[key])
 for n,f in m[group].items():
  raw=(R/n).read_bytes();assert raw==(a[key][n].encode() if key=='files' else base64.b64decode(a[key][n],validate=True));assert len(raw)==f['bytes'] and sha(raw)==f['sha256'];count+=1
 for n,f in old[group].items():
  if m[group][n]!=f:changed.append(n)
assert changed==['Lumen/Views/BackupFileRecoveryView.swift','LumenUITests/LumenSmokeTests.swift']
def shipping(s):
 out=[];depth=0
 for line in s.splitlines():
  t=line.strip()
  if depth:
   if t.startswith('#if '):depth+=1
   elif t=='#endif':depth-=1
   elif depth==1:assert not t.startswith(('#else','#elseif'))
  elif t=='#if DEBUG && targetEnvironment(simulator)':depth=1
  elif t:out.append(line)
 assert depth==0;return out
view='Lumen/Views/BackupFileRecoveryView.swift';assert shipping(a['files'][view])==shipping(prior['files'][view])
callback='confirmationLifecycleCheckValue = HealthConfirmationLifecycleTrace.check(\n                            session: session.id, request: UUID())'
assert a['files'][view].count(callback)==prior['files'][view].count(callback)==1
v=a['files'][view];control=v.index('Button("Check cancellation")');assert v.rfind('Section {',0,control)>v.index('ForEach(BackupDomain.allCases') if 'ForEach(BackupDomain.allCases' in v else v.rfind('Section {',0,control)>0
assert v.index('Section {\n                    Button("Check cancellation")')<v.index('Text(preservation)')
key='LumenUITests/LumenSmokeTests.swift';s=a['files'][key];p=prior['files'][key];start='    @MainActor\n    func testHealthBackupFileRecoveryTargetChangedDuringConfirmationNotNowOriginData()';end='    @MainActor\n    func testHealthBackupFileRecoveryHealthyTargetAfterReadyOriginData()'
def split(s):
 x=s.index(start);y=s.index(end,x);return s[:x],s[x:y],s[y:]
before,body,after=split(s);pb,pbody,pa=split(p);assert before==pb and after==pa
permission=body.index('try marker("dismissed"');assert body.index('try require(choice.isEnabled && choice.value as? String == (index == 0 ? "1" : "0")')<permission
assert body.index('"phase": "not-now-tap"')<body.index('"phase": "not-now-dismissal"')<permission
assert body.count('missingAbove: index == 0')==1 and body.count('nativeSwitch(')==pbody.count('nativeSwitch(')
observed=body.index('_ = observeCheck("check-acquisition-before-reveal"');whole=body.index('try whole(check, "check-reveal"');ready=body.index('let checkReady = observeCheck("check-acquisition-before-touch")');guard=body.index('try require(checkReady');tap=body.index('check.tap()');assert permission<observed<whole<ready<guard<tap
assert 'for attempt in 0..<16' in body
for phrase in ['count == 1 && exists && enabled && hittable && wholeFrame','navigationPresent && identifier == "checkConfirmationLifecycle" && roleIsButton','frame.width >= 44 && frame.height >= 44','appFrame.contains(frame) && viewport.contains(frame)','observations.append(fact)'] : assert phrase in body
sdk=load('source254-uitest-sdk-typecheck-r1.json');assert sdk['exit']==0 and not sdk['stdout'] and not sdk['stderr'] and sdk['sha256']==m['files'][key]['sha256'] and sdk['bytes']==m['files'][key]['bytes']
controls=load('source254-finalizer-argument-controls-r1.json');assert controls['count']==18 and not controls['processQueries'];f=controls['actualFinalizer'];assert {'bytes':f['bytes'],'sha256':f['sha256']}==m['files'][str(B.relative_to(R)/f['file'])]
runner=load('source254-runner-reference-controls-r1.json');assert runner['count']==20 and not runner['realProcessQueries'] and runner['actualManifest']==m['source']
for n,f in runner['sources'].items():assert m['files'][str(B.relative_to(R)/n)]==f
for k in ['checkedDevelopmentMarkers','debugPositiveControls','negativeMarkersWithoutDebugPositive','verifiedProductionMarkers']:assert load('health-current-release-source254-r1-predeclared-plan.json')[k]==load('health-current-release-source253-r1-predeclared-plan.json')[k]
proof=load('source253-native-exact-github.json');assert proof['commit']=='c7ea6a84a7bf967a2ecfc3af381364bee0919177' and proof['unionPaths']==2041
cleanup=load('source254-completed-failed252-cleanup-r1.json');assert cleanup['creditedRecoveryBytes']==102301696 and cleanup['aggregateCreditedRecoveryBytes']==15174045271
result={'status':'PASS current/archive, only DEBUGsim placement and dedicated native method changes, shipping projection exact, SDK0,18argument/20runner controls; independent source review pending','source':m['source'],'bindings':count,'priorModified':changed,'priorUnchanged':903-len(changed),'appended':count-903,'scope':'Actual full SwiftUI compile/current pair/native acquisition/tap/freshcheck/Back/Release not yet verified. No retrospective253acceptance. No old raw/sourcebound checker rerun.','checkedAt':time.time()}
p=B/'source254-root-preparation-r1.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
