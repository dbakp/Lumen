from pathlib import Path
import os,json,hashlib,subprocess,stat,shutil,time
p=Path('Design/native/health-write-order');sha=lambda b:hashlib.sha256(b).hexdigest()
paths=json.loads(Path('/tmp/lumen210-release-publish-paths.json').read_text())
for name in paths:assert Path(name).read_bytes()==subprocess.check_output(['git','show','origin/main:'+name]),name
review=json.loads((p/'health-current-release-source210-round2-part68.json').read_text())
target=Path('/tmp/LumenBatch37Release');assert target.is_dir() and not target.is_symlink()
for row in review['actualKnownArtifactBindings']:
 f=Path(row['file'])
 if f.is_relative_to(target):
  b=f.read_bytes();assert len(b)==row['bytes'] and sha(b)==row['sha256']
opened=subprocess.run(['lsof','-t','+D',str(target)],capture_output=True,text=True)
assert opened.returncode==1 and not opened.stdout and not opened.stderr,opened.stdout+opened.stderr
processes=subprocess.check_output(['ps','-axo','pid,command'],text=True)
assert not any('xcodebuild' in line and '/tmp/LumenBatch37Release' in line for line in processes.splitlines()),'Release process still active'
allocated=0;regular=0;symlinks=0;todo=[target]
while todo:
 f=todo.pop();s=f.lstat()
 if stat.S_ISLNK(s.st_mode):symlinks+=1
 elif stat.S_ISDIR(s.st_mode):todo.extend(f.iterdir())
 else:assert stat.S_ISREG(s.st_mode);allocated+=s.st_blocks*512;regular+=1
before=shutil.disk_usage('.').free
shutil.rmtree(target)
after=shutil.disk_usage('.').free
out={'status':'PASS completed task-owned Release build output removed after exact22path reviewed checkpoint; no immediate reuse','exactGithubMain':subprocess.check_output(['git','rev-parse','origin/main'],text=True).strip(),'exactBackupPaths':paths,'removedPath':str(target),'allocatedRegularFileBytes':allocated,'regularFiles':regular,'symlinksRemovedWithoutFollowing':symlinks,'availableBytesBefore':before,'availableBytesAfter':after,'observedFreeDeltaBytes':after-before,'positiveRecoveryCreditBytes':max(0,after-before),'scope':'Only obsolete Release DerivedData. Current Debug simulator/package cache retained for immediate211test-onlygate. Canonical original evidence/source/audits/logs remain. No global caches/other projects/simulators/userfiles removed; no cleanup-only build. Raw artifact paths are now historical.','checkedAt':time.time()}
(p/'source210-release-build-cleanup-r1.json').write_text(json.dumps(out,indent=2)+'\n')
print({k:v for k,v in out.items() if k not in ['exactBackupPaths','scope']})
