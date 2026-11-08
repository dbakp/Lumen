"""Root current frozen source/control audit; no builds or simulator queries."""
from pathlib import Path
import ast,base64,gzip,hashlib,json,time
B=Path(__file__).resolve().parent;R=B.parents[2];sha=lambda x:hashlib.sha256(x).hexdigest();load=lambda n:json.loads((B/n).read_bytes())
m=load('durable-source-r250.json');a=json.loads(gzip.decompress((B/'durable-source-r250.json.gz').read_bytes()));prior=load('durable-source-r249.json');changed=[];count=0
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(a[key])
 for n,f in m[group].items():
  p=R/n;assert not p.is_symlink();raw=p.read_bytes();assert len(raw)==f['bytes'] and sha(raw)==f['sha256'];assert raw==(a[key][n].encode() if key=='files' else base64.b64decode(a[key][n],validate=True));count+=1
 for n,f in prior[group].items():
  if m[group][n]!=f:changed.append(n)
assert sorted(changed)==['Lumen/Views/BackupFileRecoveryView.swift','Lumen/Views/HealthConfirmationTargetChangeGate.swift','Lumen/Views/HealthLegacyTargetChangeUIFixture.swift','LumenUITests/LumenSmokeTests.swift']
old=json.loads(gzip.decompress((B/'durable-source-r249.json.gz').read_bytes()))['files']
key='LumenUITests/LumenSmokeTests.swift';current=a['files'][key];start=current.index('    @MainActor\n    func testHealthBackupFileRecoveryTargetChangedDuringConfirmationNotNowOriginData()');end=current.index('    @MainActor\n    func testHealthBackupFileRecoveryHealthyTargetAfterReadyOriginData()',start)
setup='                if name.contains("DuringConfirmationNotNow") { app.launchArguments.append("-health-legacy-confirmation-lifecycle-ui") }\n'
assert current.count(setup)==1 and (current[:start]+current[end:]).replace(setup,'')==old[key]
for name in ['source250-lifecycle-controls-r1.json','source250-lifecycle-caller-controls-r1.json','source250-entrypoint-controls-r1.json']:
 report=load(name);assert report['status'].startswith('PASS')
 if 'fixture' in report:
  raw=gzip.decompress((B/report['fixture']).read_bytes());assert len(raw)==report['decodedBytes'] and sha(raw)==report['decodedSHA256'];json.loads(raw)
for name in ['source250-native-lifecycle-controls-r2.json','source250-native-guard-controls-r1.json']:
 report=load(name);assert report['status'].startswith('PASS') and report['compileExit']==report['runExit']==0
 raw=gzip.decompress((B/report['fixture']).read_bytes());assert len(raw)==report['decodedBytes'] and sha(raw)==report['decodedSHA256'];full=json.loads(raw)
 assert not full.get('compileStderr') and not full.get('runStderr')
 if 'sources' in report:
  assert all(m['files'][k]==v for k,v in report['sources'].items())
 else:assert report['actualSourceSHA256']==m['files']['Lumen/Views/HealthLegacyTargetChangeUIFixture.swift']['sha256']
for kind in ['uitest','lifecycle']:
 report=load('source250-'+kind+'-sdk-typecheck-r2.json');assert report['exit']==0 and not report['stdout'] and not report['stderr']
 for source in report['sources']:assert {k:source[k] for k in ['bytes','sha256']}==m['files'][source['file']]
for name in ['confirmation-lifecycle-driver-r1.py','check-confirmation-lifecycle-r1.py']:ast.parse((B/name).read_text())
plan=load('health-current-release-source250-r1-predeclared-plan.json');oldplan=load('health-current-release-source249-r1-predeclared-plan.json')
new=['-health-legacy-confirmation-lifecycle-ui','Lumen-confirmation-lifecycle-verification-v1','Lumen-confirmation-lifecycle-','checkConfirmationLifecycle']
for key in ['checkedDevelopmentMarkers','debugPositiveControls']:assert plan[key]==oldplan[key]+new
for key in ['negativeMarkersWithoutDebugPositive','verifiedProductionMarkers']:assert plan[key]==oldplan[key]
proof=load('source250-plan-exact-github.json');assert proof['commit']=='c9ed383bbd0d6e019a53a16716a11b47c9221903' and proof['unionPaths']==1845
result={'status':'PASS root current/archive/bounded separate lifecycle implementation/isolated controls/current SDK typing/predeclared arrays; independent source readiness pending','source':'durable-source-r250.json','bindings':count,'priorModified':changed,'priorUnchanged':816-len(changed),'appended':count-816,'controls':{'isolatedPredicatesPublishers':33,'actualCaller':13,'actualMacSchedulingCases':4,'actualExtractedContextFixedGuards':37,'help':2},'scope':'DEBUG+sim-only lifecycle evidence plus actual separate Notnow XCTest/host/checker. Whole current app body/build/native timing/actual iOS worker completion/lateack/freshread/Release/expiry/otherwindows/retainedowner/fullgoal remain unproved. Failed initial import and missing Foundation harness compile preserved; R2 scheduling and SDK typing supersede named initial preparations only.','checkedAt':time.time()}
out=B/'source250-root-preparation-r1.json';assert not out.exists();out.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
