"""Root current finalizer-only successor with historical control qualifications."""
from pathlib import Path
import ast,base64,gzip,hashlib,json,time
B=Path(__file__).resolve().parent;R=B.parents[2];load=lambda n:json.loads((B/n).read_bytes());sha=lambda x:hashlib.sha256(x).hexdigest()
m=load('durable-source-r255.json');a=json.loads(gzip.decompress((B/'durable-source-r255.json.gz').read_bytes()));old=load('durable-source-r254.json');count=0
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(a[key])
 for n,f in m[group].items():
  raw=(R/n).read_bytes();assert raw==(a[key][n].encode() if key=='files' else base64.b64decode(a[key][n],validate=True));assert len(raw)==f['bytes'] and sha(raw)==f['sha256'];count+=1
 for n,f in old[group].items():assert m[group][n]==f,n
assert count==951
for kind,nested,expected in [('argument','actualFinalizer',18),('caller','actualSource',11)]:
 d=load('source255-finalizer-'+kind+'-controls-r2.json');assert d['count']==expected;f=d[nested];raw=(B/f['file']).read_bytes();assert len(raw)==f['bytes'] and sha(raw)==f['sha256']
 assert not d.get('processQueries',d.get('realProcessQueries'))
caller=load('source255-finalizer-caller-controls-r2.json');assert all(x['actualMainRan'] and x['fullUnfilteredAcquisitionAttempted'] and x['syntheticOriginalsRetained']==2 for x in caller['cases'])
for row in caller['cases']:
 assert (row['finalFailure'] is None)==(row['case'] in ['coherent-native-success','coherent-native-rejection'])
 if row['case']=='query-write-failure':assert row['stageErrors'] and row['actualQueryRetainedBeforeExport']
oldraw=(B/'source255-finalizer-before-bounded-read-r1.py').read_bytes()
for kind,nested in [('argument','actualFinalizer'),('caller','actualSource')]:
 f=load('source255-finalizer-'+kind+'-controls-r1.json')[nested];assert len(oldraw)==f['bytes'] and sha(oldraw)==f['sha256']
runner=load('source255-runner-reference-controls-r1.json');assert runner['count']==20 and not runner['realProcessQueries'] and runner['actualManifest']==m['source']
for n,f in runner['sources'].items():assert m['files'][str(B.relative_to(R)/n)]==f
sdk=load('source254-uitest-sdk-typecheck-r1.json');assert sdk['exit']==0 and not sdk['stdout'] and not sdk['stderr'] and m['files'][sdk['file']]=={'bytes':sdk['bytes'],'sha256':sdk['sha256']}
for k in ['checkedDevelopmentMarkers','debugPositiveControls','negativeMarkersWithoutDebugPositive','verifiedProductionMarkers']:assert load('health-current-release-source255-r1-predeclared-plan.json')[k]==load('health-current-release-source254-r1-predeclared-plan.json')[k]
proof=load('source254-source-exact-github-r2.json');assert proof['commit']=='bc26cc4eee4d80aa6a8edf710a95c854e4fad74c' and proof['checkpointPaths']==36 and proof['unionPaths']==2066
result={'status':'PASS current951/archive/all924priorunchanged/18pure+11actual-main-injected+20runnercontrols/exact2066 before255; source review pending','source':m['source'],'bindings':count,'priorUnchanged':924,'priorModified':[],'appended':27,'historicalQualification':'R1 controls preceded bounded8MiB audit read; exact old helper retained as source255-finalizer-before-bounded-read-r1.py, hash matches both R1 receipts. Current R2 controls bind current R3. Pre-freeze syntax failure retained; no child/export/native executed by that failed compile. Initial254proof used wrong historical pathlist; separate R2 actual36checkpoint2066 union exact before255, qualification preserves initial limited proof.','scope':'Actual main persistence/archive/error latches tested with synthetic child/export/path dependencies only. No real current build/Debug markers/native/Check/Back/Release acceptance. App/test exact254 SDK carry; full SwiftUI and current pair stillrequired. Best-effort query/audit persistence; no blanket filesystem/process-failure salvage guarantee.','checkedAt':time.time()}
p=B/'source255-root-preparation-r1.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
