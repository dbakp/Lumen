from pathlib import Path
import json,hashlib,gzip,subprocess,stat,shutil,time
p=Path('Design/native/health-write-order');sha=lambda b:hashlib.sha256(b).hexdigest()
outcome=json.loads((p/'source210-logic-r1-outcome.json').read_text())
proofs=['source210-logic-r1-outcome.json','durable-source-r210.json','durable-source-r210.json.gz','health-legacy-root-acquisition-source210-round2-part62-production-repair.json','source210-legacy-origin-r1-live-audit.json','source210-legacy-boundaries-r1-live-audit.json','source210-legacy-transaction-r1-live-audit.json']
for row in outcome['runs']:
 assert row['exitCode']==0
 proofs.append(row['log'])
 b=gzip.decompress((p/row['log']).read_bytes());assert len(b)==row['logBytes'] and sha(b)==row['logSHA256']
 if 'report' in row:proofs.append(row['report'])
for name in proofs:assert (p/name).read_bytes()==subprocess.check_output(['git','show','origin/main:'+str(p/name)]),name
target=Path('/tmp/LumenLogicBuild');assert target.is_dir() and not target.is_symlink()
binary=Path(outcome['binary']['path']);b=binary.read_bytes();assert len(b)==outcome['binary']['bytes'] and sha(b)==outcome['binary']['sha256']
opened=subprocess.run(['lsof','-t','+D',str(target)],capture_output=True,text=True)
assert opened.returncode==1 and not opened.stdout and not opened.stderr,opened.stdout+opened.stderr
processes=subprocess.check_output(['ps','-axo','pid,command'],text=True)
assert not any(('/tmp/LumenLogicBuild' in line or '/private/tmp/LumenLogicBuild' in line) and ('swift' in line or 'LumenLogicChecks' in line) for line in processes.splitlines())
allocated=0;regular=0;links=0;todo=[target]
while todo:
 f=todo.pop();s=f.lstat()
 if stat.S_ISLNK(s.st_mode):links+=1
 elif stat.S_ISDIR(s.st_mode):todo.extend(f.iterdir())
 else:assert stat.S_ISREG(s.st_mode);allocated+=s.st_blocks*512;regular+=1
before=shutil.disk_usage('.').free;shutil.rmtree(target);after=shutil.disk_usage('.').free
r={'status':'PASS obsolete completed210 pure Swift scratch cache removed after exact immutable GitHub source/outcome/log/focus/liveaudit proofs','exactGithubMain':subprocess.check_output(['git','rev-parse','origin/main'],text=True).strip(),'exactProofPaths':[str(p/name) for name in proofs],'removedPath':str(target),'allocatedRegularFileBytes':allocated,'regularFiles':regular,'symlinksRemovedWithoutFollowing':links,'availableBytesBefore':before,'availableBytesAfter':after,'observedFreeDeltaBytes':after-before,'positiveRecoveryCreditBytes':max(0,after-before),'retained':'Current212simulator/package caches and ALL pure source/reports/focusfixtures/defaultssuites retained. No fixture cleanup by this helper. Native active case uses distinct cache; no pure build/test/openFD present.','scope':'No immediate pure cache reuse: current changes only native tests/harness. No new tests/build for cleanup, no test-count expansion, no other projects/global cache/simulator/userfile deletion.','checkedAt':time.time()}
(p/'source212-obsolete-pure-cache-cleanup-r1.json').write_text(json.dumps(r,indent=2)+'\n');print({k:v for k,v in r.items() if k not in ['exactProofPaths','retained','scope']})
