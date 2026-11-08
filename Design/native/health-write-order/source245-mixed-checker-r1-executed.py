"""Execute the mandatory readonly R2 checker once and retain any actual failure."""
from pathlib import Path
import gzip,hashlib,json,subprocess,time
B=Path('Design/native/health-write-order');output=B/'source245-mixed-r1-checker-execution.json';assert not output.exists();command=['python3','-B',str(B/'check-mixed-ineligible-evidence-r2.py'),'health-mixed-ineligible-source245r1','source245-mixed-r1-checker.json','--host-source','durable-source-r245.json'];started=time.time();process=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE);stdout,stderr=process.communicate();code=process.returncode;streams={}
for key,data in [('stdout',stdout),('stderr',stderr)]:
 p=B/('source245-mixed-r1-checker-'+key+'.gz');assert not p.exists();p.write_bytes(gzip.compress(data,mtime=0));streams[key]={'retained':p.name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
out={'status':'PASS actual mandatoryR2readonlychecker' if code==0 else 'FAILED actual mandatoryR2readonlychecker; no acceptance','command':command,'checkerExit':code,'checkerPID':process.pid,'streams':streams,'started':started,'finished':time.time(),'scope':'One readonly currentcase checker; no native rerun/reset/defaults repair/build/phoneactions'};output.write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out));raise SystemExit(code)
