import pathlib,json,subprocess,shutil,gzip,time,stat,os
p=pathlib.Path('Design/native/health-write-order');paths=json.loads(pathlib.Path('/tmp/lumen210-ui-legacy-publish-paths.json').read_text())
for name in paths:assert pathlib.Path(name).read_bytes()==subprocess.check_output(['git','show','origin/main:'+name]),name
for f in ['health-error-state-legacy-source210r4-images.json','health-error-state-legacy-source210r4-readbacks.json']:
 for r in json.loads((p/f).read_text()):assert (p/r['file']).read_bytes()==pathlib.Path(r['raw']).read_bytes()
base=pathlib.Path('/tmp/LumenBatch44Checks/HealthErrorStateLegacySource210R4');targets=[pathlib.Path(str(base)+s) for s in ['.xcresult','PNG','JSON','.log','-summary.json']]
assert gzip.decompress((p/'HealthErrorStateLegacySource210R4.log.gz').read_bytes())==targets[3].read_bytes()
assert json.loads(targets[4].read_text())==json.loads((p/'health-error-state-legacy-source210r4-summary.json').read_text())
allocated=0
for f in targets:
 assert f.exists() and not f.is_symlink()
 opened=subprocess.run(['lsof','-t','+D',str(f)] if f.is_dir() else ['lsof','-t',str(f)],capture_output=True,text=True)
 assert opened.returncode==1 and not opened.stdout and not opened.stderr,opened.stdout+opened.stderr
 todo=[f]
 while todo:
  x=todo.pop();s=x.lstat();assert not stat.S_ISLNK(s.st_mode)
  if stat.S_ISDIR(s.st_mode):todo.extend(x.iterdir())
  else:assert stat.S_ISREG(s.st_mode);allocated+=s.st_blocks*512
before=shutil.disk_usage('.').free
for f in targets:
 if f.is_dir():shutil.rmtree(f)
 else:f.unlink()
after=shutil.disk_usage('.').free
ledger={'status':'PASS completed210Data rawduplicates removed afterall39exactcheckpoint paths; canonical19originalPNG/full443BJSON preserved','exactGithubMain':subprocess.check_output(['git','rev-parse','origin/main'],text=True).strip(),'exactBackupPaths':paths,'removedPaths':list(map(str,targets)),'allocatedFileBytesRemoved':allocated,'availableBytesBefore':before,'availableBytesAfter':after,'observedFreeDeltaBytes':after-before,'positiveRecoveryCreditBytes':max(0,after-before),'canonicalOriginalImagesRetained':19,'canonicalCompleteNativeJSONRetained':1,'scope':'Only completedData rawbundle/export/log/summary. Current210build cache/source/report/critic, all canonical originals and provenance, othercases/191video/inputs/simulator/userfiles remain. Rawpaths historical. Background/APFS activity may affect free delta; allocated bytes separate.','checkedAt':time.time()}
(p/'source210-origin-legacy-r4-raw-cleanup.json').write_text(json.dumps(ledger,indent=2)+'\n');print({k:v for k,v in ledger.items() if k not in ['exactBackupPaths','removedPaths','scope']})
