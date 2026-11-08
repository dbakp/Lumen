"""Root current native-only reveal/diagnostic repair and source preparation."""
from pathlib import Path
import base64,gzip,hashlib,json,time
B=Path(__file__).resolve().parent;R=B.parents[2];sha=lambda x:hashlib.sha256(x).hexdigest();load=lambda n:json.loads((B/n).read_bytes())
m=load('durable-source-r253.json');a=json.loads(gzip.decompress((B/'durable-source-r253.json.gz').read_bytes()));old=load('durable-source-r252.json');previous=json.loads(gzip.decompress((B/'durable-source-r252.json.gz').read_bytes()));count=0;changed=[]
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(a[key])
 for n,f in m[group].items():
  raw=(R/n).read_bytes();assert raw==(a[key][n].encode() if key=='files' else base64.b64decode(a[key][n],validate=True));assert len(raw)==f['bytes'] and sha(raw)==f['sha256'];count+=1
 for n,f in old[group].items():
  if m[group][n]!=f:changed.append(n)
assert changed==['LumenUITests/LumenSmokeTests.swift']
key=changed[0];current=a['files'][key];prior=previous['files'][key]
start='    @MainActor\n    func testHealthBackupFileRecoveryTargetChangedDuringConfirmationNotNowOriginData()';end='    @MainActor\n    func testHealthBackupFileRecoveryHealthyTargetAfterReadyOriginData()'
def split(source):
 x=source.index(start);y=source.index(end,x);return source[:x],source[x:y],source[y:]
before,body,after=split(current);oldbefore,oldbody,oldafter=split(prior);assert before==oldbefore and after==oldafter
assert body.count('missingAbove: index == 0')==1
assert 'let direction: CGFloat = exists ? (frame.midY < box.midY ? -1 : 1) : (missingAbove ? -1 : 1)' in body
assert body.count('nativeSwitch(')==oldbody.count('nativeSwitch(')
assert body[body.index('let args = app.launchArguments'):body.index('        do {\n            tab("Today")')]==oldbody[oldbody.index('let args = app.launchArguments'):oldbody.index('        do {\n            tab("Today")')]
tap=body.index('"phase": "not-now-tap"');dismiss=body.index('"phase": "not-now-dismissal"');loop=body.index('            for (index, choice) in [app.switches["recoverFile-meals"]');permission=body.index('try marker("dismissed"');assert tap<dismiss<loop<permission
assert body.index('try require(choice.isEnabled && choice.value as? String == (index == 0 ? "1" : "0")')<permission
assert 'if exists && target.isHittable && box.contains(frame) { return }' in body and 'for attempt in 0..<16' in body
sdk=load('source253-uitest-sdk-typecheck-r1.json');assert sdk['exit']==0 and not sdk['stdout'] and not sdk['stderr'] and sdk['sha256']==m['files'][key]['sha256'] and sdk['bytes']==m['files'][key]['bytes']
report=load('source253-runner-reference-controls-r1.json');assert report['count']==20 and not report['realProcessQueries'] and report['actualManifest']=='durable-source-r253.json'
for n,f in report['sources'].items():assert m['files']['Design/native/health-write-order/'+n]==f
for k in ['checkedDevelopmentMarkers','debugPositiveControls','negativeMarkersWithoutDebugPositive','verifiedProductionMarkers']:assert load('health-current-release-source253-r1-predeclared-plan.json')[k]==load('health-current-release-source252-r1-predeclared-plan.json')[k]
proof=load('source252-native-exact-github.json');assert proof['commit']=='dcc4de89cb73007e5d0bf22a595c8aabb0992235' and proof['unionPaths']==1971
cleanup=load('source253-completed-failed252-cleanup-r1.json');assert cleanup['creditedRecoveryBytes']==140926976 and cleanup['aggregateCreditedRecoveryBytes']==15071743575
result={'status':'PASS root current/archive/onlydedicatedNotnow testmethod changed/SDK0/20actualrunnercontrols/strictmarkerorder/arrays/prior1971exact; source review pending','source':'durable-source-r253.json','bindings':count,'priorUnchanged':886,'priorModified':changed,'appended':count-887,'scope':'App/Shared/R2host/checker unchanged252. Test-only repair; no current253pair or actualnavigation/choices/lateack/Check/Back/native/Release acceptance. Actual252/166 remainsfailed and historical raw252paths alreadyremoved after1971exact, never rerun oldlive/rawsourceboundaudits.','checkedAt':time.time()}
p=B/'source253-root-preparation-r1.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
