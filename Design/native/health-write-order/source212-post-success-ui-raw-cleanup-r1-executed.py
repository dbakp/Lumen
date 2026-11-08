from pathlib import Path
import json,subprocess,hashlib,gzip,stat,shutil,time
p=Path('Design/native/health-write-order');sha=lambda b:hashlib.sha256(b).hexdigest()
proofs=sorted(set(json.loads(Path('/tmp/lumen212-data-publish-paths.json').read_text())+json.loads(Path('/tmp/lumen212-string-publish-paths.json').read_text())))
for name in proofs:assert Path(name).read_bytes()==subprocess.check_output(['git','show','origin/main:'+name]),name
cases=[('HealthErrorStateLegacySource212R1','health-error-state-legacy-source212r1'),('HealthErrorStateEncryptedSource212R2','health-error-state-encrypted-source212r2')]
targets=[];caseFacts=[]
for stem,prefix in cases:
 for kind in ['images','readbacks']:
  rows=json.loads((p/(prefix+'-'+kind+'.json')).read_text())
  assert len(rows)==(20 if kind=='images' else 1)
  for r in rows:
   b=(p/r['file']).read_bytes();assert b==Path(r['raw']).read_bytes() and len(b)==r['bytes'] and sha(b)==r['sha256']
 raw=Path('/tmp/LumenBatch44Checks')/stem
 own=[Path(str(raw)+suffix) for suffix in ['.xcresult','PNG','JSON','.log','-summary.json']]
 assert gzip.decompress((p/(stem+'.log.gz')).read_bytes())==own[3].read_bytes()
 assert json.loads(own[4].read_bytes())==json.loads((p/(prefix+'-summary.json')).read_bytes())
 targets.extend(own);caseFacts.append({'stem':stem,'canonicalOriginals':20,'canonicalFullNativeJSON':1})
allocated=0;regular=0
for target in targets:
 assert target.exists() and not target.is_symlink()
 opened=subprocess.run(['lsof','-t','+D',str(target)] if target.is_dir() else ['lsof','-t',str(target)],capture_output=True,text=True)
 assert opened.returncode==1 and not opened.stdout and not opened.stderr,opened.stdout+opened.stderr
 todo=[target]
 while todo:
  f=todo.pop();s=f.lstat();assert not stat.S_ISLNK(s.st_mode)
  if stat.S_ISDIR(s.st_mode):todo.extend(f.iterdir())
  else:assert stat.S_ISREG(s.st_mode);allocated+=s.st_blocks*512;regular+=1
before=shutil.disk_usage('.').free
for target in targets:
 if target.is_dir():shutil.rmtree(target)
 else:target.unlink()
after=shutil.disk_usage('.').free
d={'status':'PASS obsolete raw bundles/exports/logs/summaries for both completed212UIcases removed after exact reviewed GitHub backups','exactGithubMain':subprocess.check_output(['git','rev-parse','origin/main'],text=True).strip(),'exactBackupPaths':proofs,'cases':caseFacts,'removedPaths':list(map(str,targets)),'allocatedRegularFileBytes':allocated,'regularFiles':regular,'availableBytesBefore':before,'availableBytesAfter':after,'observedFreeDeltaBytes':after-before,'positiveRecoveryCreditBytes':max(0,after-before),'scope':'Only ten named disposable rawtargets. All40canonical originalPNG/full1943BnativeJSON/source/archive/complete compact protocols/receipt/typed/v2/evidence/critic/source211finding retained. Datafalseindex+erratum retained unchanged. Current212native/packagecache/liveString23filetree/defaults/syntheticinputs/video/otherprojects/otherSimulators/userfiles untouched; no cleanup-only build. Raw artifact references now historical.','checkedAt':time.time()}
(p/'source212-post-success-ui-raw-cleanup-r1.json').write_text(json.dumps(d,indent=2)+'\n');print({k:v for k,v in d.items() if k not in ['exactBackupPaths','removedPaths','scope']})
