"""Root exact NOT_READY164/source875 checkpoint before separate252 correction."""
from pathlib import Path
import base64,gzip,hashlib,json,shutil,time
B=Path(__file__).resolve().parent;R=B.parents[2];sha=lambda x:hashlib.sha256(x).hexdigest()
name='health-legacy-confirmation-lifecycle-source251-round2-part164-source.json';raw=(B/name).read_bytes();report=json.loads(raw)
assert len(raw)==18132 and sha(raw)=='9e19a9dcc2fedf56bc8c738d3ced612405269a2179872b0d3a9a4a32894ed61a'
assert report['part']==164 and report['verdict']['sourceReady'] is False and report['verdict']['stopBeforeBuild'] is True
assert len(report['provenance'])==40
for row in report['provenance']:
 data=(R/row['path']).read_bytes();assert len(data)==row['bytes'] and sha(data)==row['sha256']
m=json.loads((B/'durable-source-r251.json').read_bytes());a=json.loads(gzip.decompress((B/'durable-source-r251.json.gz').read_bytes()));count=0
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(a[key])
 for n,f in m[group].items():
  data=(R/n).read_bytes();assert data==(a[key][n].encode() if key=='files' else base64.b64decode(a[key][n],validate=True));assert len(data)==f['bytes'] and sha(data)==f['sha256'];count+=1
assert count==875
result={'status':'Root acknowledges164 NOT_READY; retain full251/875/40bindings before252runner source corrections','report':{'file':name,'bytes':len(raw),'sha256':sha(raw)},'allReportBindingsExact':40,'allCurrentArchiveBindingsExact':875,'rootRead':'Full18132B report opened in two nontruncated1-175/176-end ranges. Requested163checker+waiter fixes supported at source scope. Actual plannedrunners read/rg independentlyconfirms stale248/249 source loads and output fields.','requiredCorrection':'P164-C1 correct allthree separate successor plannedrunners manifest/archive/outcome/receipt/binder+human source labels; actual AST/reference/prelaunch consistency controls beforebuild','scope':'No250/251currentapp/native/Release acceptance; unchangedappSDK/mac controls carryonly. Fullgoal active, no checkpointstop/phoneactions/oldraw audit.','visualCheck':'Markup/3buttons/savedstates/fallback VM pass; no browser render','availableBytes':shutil.disk_usage(R).free,'checkedAt':time.time()}
p=B/'source251-root-part164-review.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n');print(result['status'])
