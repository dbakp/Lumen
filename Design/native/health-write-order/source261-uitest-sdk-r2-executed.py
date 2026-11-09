"""Fence and SDK-typecheck the whole new UITest source; no app build or simulator action."""
from pathlib import Path
import base64,hashlib,json,shutil,subprocess,time
B=Path(__file__).resolve().parent;R=B.parents[2];source=R/'LumenUITests/LumenSmokeTests.swift'
output=B/'source261-uitest-sdk-r2.json';assert not output.exists()
old=json.loads((B/'source258-uitest-sdk-r4.json').read_bytes());command=old['command']
assert command[-1]==str(source) and command[1:3]==['swiftc','-typecheck']
before=source.read_bytes();started=time.time();process=subprocess.Popen(command,cwd=R,stdout=subprocess.PIPE,stderr=subprocess.PIPE);out,err=process.communicate();after=source.read_bytes()
sha=lambda data:hashlib.sha256(data).hexdigest()
result={'status':'PASS whole actual UITest SDK typing' if process.returncode==0 and before==after else 'FAILED','kind':'uitest','command':command,'pid':process.pid,'exit':process.returncode,'beforeBytes':len(before),'beforeSHA256':sha(before),'afterBytes':len(after),'afterSHA256':sha(after),'sourceFenceExact':before==after,'stdout':base64.b64encode(out).decode(),'stderr':base64.b64encode(err).decode(),'startedAt':started,'finishedAt':time.time(),'availableBytes':shutil.disk_usage(R).free,'scope':'Whole actual new UITest source SDK typing, no stubs. Explicit260 production/app/Core unchanged carry; no new app/test build or native acceptance.'}
output.write_text(json.dumps(result,indent=2)+'\n');print(result['status']);print(err.decode(errors='replace'));raise SystemExit(not result['status'].startswith('PASS'))
