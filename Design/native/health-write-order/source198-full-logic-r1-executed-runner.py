import json,gzip,hashlib,subprocess,time,shutil,re
from pathlib import Path
p=Path('Design/native/health-write-order');raw=Path('/tmp/LumenBatch44Checks');m=json.loads((p/'durable-source-r198.json').read_text());sha=lambda b:hashlib.sha256(b).hexdigest()
def verify():
 for group in ['files','fixtureInputs']:
  for name,r in m[group].items():
   f=Path(name);assert not f.is_symlink();b=f.read_bytes();assert len(b)==r['bytes'] and sha(b)==r['sha256'],name
verify();free=shutil.disk_usage(Path.cwd()).free;assert free>8*1024**3;binary=Path('/tmp/LumenLogicBuild/debug/LumenLogicChecks');identity=sha(binary.read_bytes());assert identity=='45440c37ceaab86acae129a4867ea8d192e2ac677c93702ab47a070574fe8831';log=raw/'Source198FullLogicR1.log';assert not log.exists();started=time.time()
with log.open('xb') as out:
 proc=subprocess.Popen([str(binary)],stdout=out,stderr=subprocess.STDOUT);subprocess.Popen(['caffeinate','-i','-w',str(proc.pid)]);print('Current198full logic suite running PID',proc.pid,flush=True);code=proc.wait()
verify();data=log.read_bytes();text=data.decode(errors='replace');name='source198-full-logic-r1.log.gz';(p/name).write_bytes(gzip.compress(data,mtime=0));d={'status':'PASS actual full current198 logic execution' if code==0 else 'FAILED actual current198 full logic execution; inspect retained failure','source':'durable-source-r198.json','exitCode':code,'processPID':proc.pid,'binarySHA256':identity,'log':name,'logBytes':len(data),'logSHA256':sha(data),'passLines':sum(x.startswith('PASS:') for x in text.splitlines()),'terminalLines':text.splitlines()[-5:],'startedAt':started,'finishedAt':time.time(),'availableBytesBefore':free,'availableBytesAfter':shutil.disk_usage(Path.cwd()).free,'scope':'Actual default complete logic executable, separately actual22fixedboundaries/117backendchecks executed; no native product integration. No currentnative/Release/fullproduct acceptance.'};(p/'source198-full-logic-r1-outcome.json').write_text(json.dumps(d,indent=2)+'\n');print(json.dumps(d),flush=True);raise SystemExit(code)
