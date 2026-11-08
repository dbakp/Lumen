"""Root current actual compile/pair/log/marker proof; no native case execution."""
from pathlib import Path
import json,gzip,base64,hashlib,time
b=Path('Design/native/health-write-order');sha=lambda x:hashlib.sha256(x).hexdigest();load=lambda n:json.loads((b/n).read_bytes())
m=load('durable-source-r252.json');a=json.loads(gzip.decompress((b/'durable-source-r252.json.gz').read_bytes()));count=0
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(a[key])
 for n,fact in m[group].items():
  raw=Path(n).read_bytes();assert raw==(a[key][n].encode() if key=='files' else base64.b64decode(a[key][n],validate=True));assert len(raw)==fact['bytes'] and sha(raw)==fact['sha256'];count+=1
assert count==887
receipt=load('health-target-change-source252-r1-build.json');out=load('source252-target-change-native-build-r1-outcome.json');assert out['source']==receipt['source']=='durable-source-r252.json' and out['exitCode']==receipt['buildExit']==0
assert receipt['sourceInputs']==825 and receipt['fixtureInputs']==62
for path,size,digest in [(Path('/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/Lumen.app/Lumen'),'binaryBytes','sha256'),(Path(receipt['testBinary']),'testBinaryBytes','testBinarySHA256')]:
 raw=path.read_bytes();assert len(raw)==receipt[size] and sha(raw)==receipt[digest]
raw=gzip.decompress((b/out['log']).read_bytes());assert raw==Path('/tmp/LumenBatch44Checks/Source252TargetChangeNativeBuildR1.log').read_bytes();assert len(raw)==out['logBytes'] and sha(raw)==out['logSHA256'];assert b'** TEST BUILD SUCCEEDED **' in raw and b': error:' not in raw and b'HealthConfirmationLifecycleTrace.swift' in raw
pre=load('health-current-release-source252-r1-predeclared-plan.json');plan=load('health-current-release-source252-r1-plan.json');controls=load('source252-current-debug-release-controls-r1.json');app=Path('/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/Lumen.app/Lumen').read_bytes()
for k in ['checkedDevelopmentMarkers','debugPositiveControls','negativeMarkersWithoutDebugPositive','verifiedProductionMarkers']:assert pre[k]==plan[k]
assert plan['source']==pre['source']=='durable-source-r252.json' and plan['debugPositiveSHA256']==receipt['sha256']==controls['debugSHA256']
assert [v for v in pre['debugPositiveControls']+pre['verifiedProductionMarkers'] if v.encode() not in app]==[]
assert [v for v in pre['checkedDevelopmentMarkers'] if v.encode() not in app]==pre['negativeMarkersWithoutDebugPositive']
assert controls['counts']=={'negative':215,'actualDebugPositive':199,'negativeOnly':16,'production':21}
proof=load('source252-source-exact-github.json');assert proof['commit']=='e49fd5f7f8a99b1ae36b938c07f2b0b0e21cfea0' and proof['unionPaths']==1924
root={'status':'PASS root actual252fullapp/testbuild0/current887archive+pair+fullactualbuildlog+2151991621controls exact; actualNotnow native pending','source':'durable-source-r252.json','bindings':count,'buildPID':out['processPID'],'buildExit':0,'appBytes':receipt['binaryBytes'],'appSHA256':receipt['sha256'],'testBytes':receipt['testBinaryBytes'],'testSHA256':receipt['testBinarySHA256'],'logBytes':out['logBytes'],'logSHA256':out['logSHA256'],'markerCounts':[215,199,16,21],'warnings':[line for line in raw.decode().splitlines() if ': warning:' in line],'scope':'CurrentwholeSwiftUIbody/newTrace and actualnative testcase compiled. Build-only: no actualNotnow/taskcompletion/lateack/freshCheck/closure/Release/fullgoal acceptance. Do not rerun single-use runner-prefix controls afterbuildlogcreated.','checkedAt':time.time()}
p=b/'source252-root-build-controls-r1.json';assert not p.exists();p.write_text(json.dumps(root,indent=2)+'\n');print(root['status'])
