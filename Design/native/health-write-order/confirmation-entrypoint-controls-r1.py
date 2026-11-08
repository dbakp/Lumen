"""Run actual entrypoint help under process-launch denial; no native run."""
import contextlib,hashlib,io,json,runpy,subprocess,sys,time
from pathlib import Path
B=Path(__file__).resolve().parent
rows=[];original={k:getattr(subprocess,k) for k in ['Popen','run','check_output','check_call','call']};queries=[]
def forbidden(*a,**k):queries.append(str(a));raise AssertionError('No process queries in help control')
try:
 for key in original:setattr(subprocess,key,forbidden)
 for name in ['confirmation-target-driver-r1.py','check-confirmation-target-r1.py']:
  stdout=io.StringIO();stderr=io.StringIO();sys.argv=[str(B/name),'--help'];code=None
  with contextlib.redirect_stdout(stdout),contextlib.redirect_stderr(stderr):
   try:runpy.run_path(str(B/name),run_name='__main__')
   except SystemExit as e:code=e.code
  assert code==0 and not stderr.getvalue() and not queries
  rows.append({'entrypoint':name,'exit':code,'stdout':stdout.getvalue(),'stderr':stderr.getvalue(),'sourceSHA256':hashlib.sha256((B/name).read_bytes()).hexdigest()})
finally:
 for key,value in original.items():setattr(subprocess,key,value)
(B/'source246-entrypoint-controls-r1.json').write_text(json.dumps({'status':'PASS both actual help0 under zeroquery guard','rows':rows,'processQueries':queries,'checkedAt':time.time(),'scope':'No native readiness or runtime acceptance'},indent=2)+'\n');print('2 actual help0 / 0queries')
