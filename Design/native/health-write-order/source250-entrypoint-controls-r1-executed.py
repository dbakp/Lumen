"""Actual argparse help must exit before any process/file producer work."""
import contextlib,hashlib,io,json,runpy,subprocess,sys,time
from pathlib import Path
B=Path(__file__).resolve().parent;queries=[]
def denied(*args,**kwargs):queries.append(str(args));raise AssertionError('No process calls during help')
for key in ['run','Popen','check_output','check_call','call']:setattr(subprocess,key,denied)
rows=[]
for name in ['confirmation-lifecycle-driver-r1.py','check-confirmation-lifecycle-r1.py']:
 stdout=io.StringIO();stderr=io.StringIO();sys.argv=[str(B/name),'--help']
 with contextlib.redirect_stdout(stdout),contextlib.redirect_stderr(stderr):
  try:runpy.run_path(str(B/name),run_name='__main__')
  except SystemExit as error:assert error.code==0
  else:raise AssertionError('Help did not exit')
 assert not queries and not stderr.getvalue()
 rows.append({'file':name,'sourceSHA256':hashlib.sha256((B/name).read_bytes()).hexdigest(),'exit':0,'stdout':stdout.getvalue(),'stderr':stderr.getvalue()})
out=B/'source250-entrypoint-controls-r1.json';assert not out.exists();out.write_text(json.dumps({'status':'PASS actual help/zero process calls','cases':rows,'realProcessQueries':queries,'checkedAt':time.time()},indent=2)+'\n');print('2 actual entrypoint help controls PASS; zero process calls')
