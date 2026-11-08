"""Read-only actual frozen host/case/pair/provider preflight under process-query guard."""
from pathlib import Path
import ast,hashlib,importlib.util,json,subprocess,time
B=Path(__file__).resolve().parent
calls=[]
def forbidden(*a,**k):calls.append(a);raise AssertionError('No device/process query in source preflight')
for name in ['run','check_output','Popen','check_call','call']:setattr(subprocess,name,forbidden)
spec=importlib.util.spec_from_file_location('safe245preflight',B/'health-mixed-ineligible-evidence-r2.py');h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
proof=h.verify_host_source('durable-source-r245.json');case=h.verify_inputs(proof['caseSource'],proof['build']);provider=h.provider();assert not calls
old_rejected=False
try:h.verify_host_source('durable-source-r244.json')
except AssertionError:old_rejected=True
assert old_rejected and not calls
old=ast.parse((B/'health-mixed-ineligible-evidence-r1.py').read_text());new=ast.parse((B/'health-mixed-ineligible-evidence-r2.py').read_text());functions=lambda tree:{x.name:ast.dump(x,include_attributes=False) for x in tree.body if isinstance(x,ast.FunctionDef)};a,c=functions(old),functions(new);names=[n for n in a if n not in ['container','provider']];assert all(a[n]==c[n] for n in names)
for name in ['health-mixed-ineligible-driver-r2.py','check-mixed-ineligible-evidence-r2.py','mixed-safe-context-controls-r1.py']:ast.parse((B/name).read_bytes())
out={'status':'PASS actual frozen245host/current244case-pair/exactapprovedprovider readonly preflight; no native execution','host':proof,'case':case,'provider':{k:v for k,v in provider.items() if k!='base64'},'rejectedCompiledOnlyManifestAsHost':old_rejected,'unchangedExistingEvidenceFunctions':names,'processDeviceQueries':len(calls),'scope':'Local frozen/archive/app-test bytes and one known syntheticprovider file only. No simulator/process/defaults command, reset, fixture seed or native acceptance.','checkedAt':time.time()};p=B/'source245-context-preflight-r1.json';assert not p.exists();p.write_text(json.dumps(out,indent=2)+'\n');print(json.dumps({k:out[k] for k in ['status','host','rejectedCompiledOnlyManifestAsHost','processDeviceQueries']}))
