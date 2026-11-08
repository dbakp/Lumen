from pathlib import Path
import subprocess,json,gzip,hashlib,time,shutil
b=Path('Design/native/health-write-order');raw=Path('/tmp/LumenBatch44Checks');binary=Path('/tmp/LumenLogicBuild/debug/LumenLogicChecks').resolve();sha=lambda x:hashlib.sha256(x).hexdigest();assert binary.is_file() and shutil.disk_usage('.').free>8*1024**3
sourceFiles=['Lumen/Models/HealthLegacyRecoveryOrigin.swift','Lumen/Views/BackupFileRecoveryView.swift','Tests/HealthLegacyRecoveryOriginChecks.swift'];before={n:sha(Path(n).read_bytes()) for n in sourceFiles};rows=[]
for label,flag in [('full',''),('legacy-origin','--health-legacy-origin'),('legacy-transaction','--health-legacy-transaction'),('legacy-boundaries','--health-legacy-boundaries')]:
 log=raw/('Source244Logic-'+label+'R1.log');report=raw/('Source244Logic-'+label+'R1.json');assert not log.exists() and not report.exists();command=[str(binary)]+([flag,str(report)] if flag else [])
 with log.open('xb') as f:
  p=subprocess.Popen(command,stdout=f,stderr=subprocess.STDOUT);subprocess.Popen(['caffeinate','-i','-w',str(p.pid)]);print('Actual244logic',label,'PID',p.pid,flush=True);code=p.wait()
 data=log.read_bytes();name='source244-logic-'+label+'-r1.log.gz';(b/name).write_bytes(gzip.compress(data,mtime=0));r={'label':label,'command':command,'processPID':p.pid,'exit':code,'log':name,'logBytes':len(data),'logSHA256':sha(data),'printedPASSLines':sum(line.startswith('PASS:') for line in data.decode().splitlines())}
 if report.exists():
  data=report.read_bytes();name='source244-logic-'+label+'-r1.json';(b/name).write_bytes(data);parsed=json.loads(data);r.update(report=name,reportBytes=len(data),reportSHA256=sha(data),reportedStatus=parsed.get('status'),checks=len(parsed.get('checks',[])),failedChecks=[x for x in parsed.get('checks',[]) if x.get('passed') is False],retainedRoot=parsed.get('retainedRoot'))
 rows.append(r)
 if code:break
assert before=={n:sha(Path(n).read_bytes()) for n in sourceFiles};out={'status':'PASS actualcurrentlogic regressions' if len(rows)==4 and all(r['exit']==0 for r in rows) else 'FAILED actualcurrentlogic regressions','binary':str(binary),'binaryBytes':binary.stat().st_size,'binarySHA256':sha(binary.read_bytes()),'sourceSHA256':before,'runs':rows,'scope':'ActualmacOS productionlogic executable only; no iOSapp/UI/newnative/Release/productcompletion acceptance','availableBytes':shutil.disk_usage('.').free,'checkedAt':time.time()};p=b/'source244-logic-regressions-r1.json';assert not p.exists();p.write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out),flush=True)
