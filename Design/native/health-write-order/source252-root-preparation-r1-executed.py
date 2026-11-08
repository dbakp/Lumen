"""Root corrected runner/current source check, no build/process/simulator action."""
from pathlib import Path
import ast,base64,gzip,hashlib,json,time
B=Path(__file__).resolve().parent;R=B.parents[2];sha=lambda x:hashlib.sha256(x).hexdigest();load=lambda n:json.loads((B/n).read_bytes())
m=load('durable-source-r252.json');a=json.loads(gzip.decompress((B/'durable-source-r252.json.gz').read_bytes()));old=load('durable-source-r251.json');count=0
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(a[key])
 for n,f in m[group].items():
  raw=(R/n).read_bytes();assert raw==(a[key][n].encode() if key=='files' else base64.b64decode(a[key][n],validate=True));assert len(raw)==f['bytes'] and sha(raw)==f['sha256'];count+=1
 for n,f in old[group].items():assert m[group][n]==f,n
report=load('source252-runner-reference-controls-r1.json');assert report['status'].startswith('PASS') and report['count']==20 and not report['realProcessQueries']
for n,f in report['sources'].items():assert m['files']['Design/native/health-write-order/'+n]==f
assert report['planSHA256']==m['files']['Design/native/health-write-order/health-current-release-source252-r1-predeclared-plan.json']['sha256']
for key in ['checkedDevelopmentMarkers','debugPositiveControls','negativeMarkersWithoutDebugPositive','verifiedProductionMarkers']:assert load('health-current-release-source252-r1-predeclared-plan.json')[key]==load('health-current-release-source251-r1-predeclared-plan.json')[key]
proof=load('source251-source-exact-github.json');assert proof['commit']=='3f8995653180fe83723d8cb9b63d039efe84b9c6' and proof['unionPaths']==1910
result={'status':'PASS root current/archive/all875prior unchanged/3runner actual source preflight AST20/arrays/prior1910exact; independent readiness pending','source':'durable-source-r252.json','bindings':count,'priorUnchanged':875,'priorModified':[],'appended':count-875,'scope':'No app/UITest/R2host/checker or authority change. No currentappcompile/Debugbinarymarkers/Release/native/Notnow/lateack/freshCheck/fullgoal acceptance. Actualrunner controls prelaunch-only, do not rerun afterbuild.','checkedAt':time.time()}
p=B/'source252-root-preparation-r1.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
