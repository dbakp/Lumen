"""Read-only actual observation-namespace interface audit; no process query."""
from pathlib import Path
import ast,hashlib,importlib.util,json,subprocess,time
B=Path(__file__).resolve().parent;path=B/'confirmation-target-driver-r2.py';tree=ast.parse(path.read_text());names=sorted({n.attr for n in ast.walk(tree) if isinstance(n,ast.Attribute) and isinstance(n.value,ast.Attribute) and isinstance(n.value.value,ast.Name) and n.value.value.id=='e' and n.value.attr=='obs'})
original={k:getattr(subprocess,k) for k in ['Popen','run','check_output','check_call','call']};queries=[]
def forbidden(*a,**k):queries.append(str(a));raise AssertionError('No process query')
try:
 for k in original:setattr(subprocess,k,forbidden)
 spec=importlib.util.spec_from_file_location('dependency_diagnostic',B/'confirmation-target-evidence-r1.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e)
 assert e.h.DEVICE=='5C4C4A6C-4D9E-4181-8794-E3925C1A7EA7';missing=[n for n in names if not hasattr(e.obs,n)]
 assert missing==['OLD'] and len(e.h.DATA)==42 and not queries
finally:
 for k,v in original.items():setattr(subprocess,k,v)
module=Path(e.obs.__file__);out={'status':'LATENT UNREACHED SOURCE BLOCKER: actual observation dependency has no OLD attribute','driver':path.name,'driverBytes':path.stat().st_size,'driverSHA256':hashlib.sha256(path.read_bytes()).hexdigest(),'actualObservationModule':module.name,'actualObservationModuleSHA256':hashlib.sha256(module.read_bytes()).hexdigest(),'requiredAttributes':names,'missingAttributes':missing,'existingKnownOldDataBytes':len(e.h.DATA),'existingKnownOldDataSHA256':hashlib.sha256(e.h.DATA).hexdigest(),'realProcessQueries':queries,'scope':'Actual module namespace inspected under process launch denial; no producer import/execution/reset/defaults mutation/phone action. Not the observed native247failure: its marker was never reached. NewData successor must use actual h.DATA and dependency-aware caller controls; original247frozen.','checkedAt':time.time()};(B/'source247-dependency-diagnostic-r1.json').write_text(json.dumps(out,indent=2)+'\n');print(out['status'])
