from pathlib import Path
import json,subprocess,hashlib,time
B=Path(__file__).resolve().parent
cmd=json.loads((B/'source258-whole-app-sdk-r1-command.json').read_text())
start=time.time(); p=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE); out,err=p.communicate()
report={'status':'PASS whole actual app SDK typecheck' if p.returncode==0 else 'FAILED whole app SDK typecheck','pid':p.pid,'exit':p.returncode,'command':cmd,'sources':[{'file':f,'bytes':len(Path(f).read_bytes()),'sha256':hashlib.sha256(Path(f).read_bytes()).hexdigest()} for f in cmd if f.endswith('.swift')],'stdout':out.decode(),'stderr':err.decode(),'scope':'Whole current app source typing with actual SDK/dependency modules and generated asset symbols, no stubs. Not full app/test link/build/native acceptance. Prior FileList used only as a source-list starting point, with both new files appended.','startedAt':start,'finishedAt':time.time()}
target=B/'source258-whole-app-sdk-r1.json';assert not target.exists();target.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'exit':p.returncode,'pid':p.pid,'diagnostics':err.decode()[-2000:]}));raise SystemExit(p.returncode)
