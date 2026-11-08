import pathlib,json,subprocess,hashlib,gzip,shutil,stat,importlib.util,time
p=pathlib.Path('Design/native/health-write-order');latest=json.loads(pathlib.Path('/tmp/lumen210-ui-legacy-publish-paths.json').read_text());verified=set()
for n in latest:assert pathlib.Path(n).read_bytes()==subprocess.check_output(['git','show','origin/main:'+n]),n;verified.add(n)
critics=['health-legacy-root-acquisition-source210-round2-part63-no-prior-safe.json','health-legacy-root-acquisition-source210-round2-part64-with-prior-safe.json','health-legacy-root-acquisition-source210-round2-part65-ordinary-control.json']
for name in critics:
 f=p/name;assert f.read_bytes()==subprocess.check_output(['git','show','origin/main:'+str(f)]);verified.add(str(f))
 for row in json.loads(f.read_text())['bindings']:
  f=pathlib.Path(row['file']) if '/' in row['file'] else p/row['file'];b=f.read_bytes();assert len(b)==row['bytes'] and hashlib.sha256(b).hexdigest()==row['sha256'];assert b==subprocess.check_output(['git','show','origin/main:'+str(f)]),str(f);verified.add(str(f))
# No app termination: the later UI app/current root remain untouched.
# Each target gets a zero-open-descriptor check below, after completed outcomes.
spec=importlib.util.spec_from_file_location('readonlyroot',p/'health-legacy-root-acquisition-driver-r1.py');driver=importlib.util.module_from_spec(spec);spec.loader.exec_module(driver)
fixtures=[];raw_targets=[];stems=[('no-prior','Source210R1','NoPrior'),('with-prior','Source210R2','WithPrior'),('ordinary','Source210R3','Ordinary')]
for case,trial,test in stems:
 prefix='root-acquisition-'+case+'-'+trial.lower();r=json.loads((p/(prefix+'-observed.json')).read_text())
 for field,key in [('movedRoot','moved'),('movedPrevious','movedPrevious')]:
  if not r[field]['root']['exists']:continue
  target=pathlib.Path(r['paths'][key]);assert target.name in ['LumenData.legacy-root-probe-'+r['runID'],'LumenData.legacy-prior-probe-'+r['runID']];assert driver.live_tree(target)==r[field]
  opened=subprocess.run(['lsof','-t','+D',str(target)],capture_output=True,text=True);assert opened.returncode==1 and not opened.stdout and not opened.stderr,opened.stdout+opened.stderr;fixtures.append(target)
 base=pathlib.Path('/tmp/LumenBatch44Checks/RootAcquisition'+test+trial);log=pathlib.Path(str(base)+'.log');assert log.read_bytes()==gzip.decompress((p/(prefix+'.log.gz')).read_bytes())
 for kind in ['png','manifest','json','other']:
  for row in json.loads((p/(prefix+'-'+kind+'-attachments.json')).read_text()):assert pathlib.Path(row['raw']).read_bytes()==(p/row['file']).read_bytes()
 for target in [pathlib.Path(str(base)+suffix) for suffix in ['.xcresult','.log','-attachments']]:
  opened=subprocess.run(['lsof','-t','+D',str(target)] if target.is_dir() else ['lsof','-t',str(target)],capture_output=True,text=True)
  assert opened.returncode==1 and not opened.stdout and not opened.stderr,opened.stdout+opened.stderr
  raw_targets.append(target)
assert len(fixtures)==4 and len(set(fixtures))==4
allocated=0
for target in fixtures+raw_targets:
 assert target.exists() and not target.is_symlink()
 for f in ([target] if target.is_file() else target.rglob('*')):
  s=f.lstat();assert not f.is_symlink()
  if stat.S_ISREG(s.st_mode):allocated+=s.st_blocks*512
  else:assert stat.S_ISDIR(s.st_mode)
before=shutil.disk_usage('.').free
for target in fixtures+raw_targets:
 if target.is_dir():shutil.rmtree(target)
 else:target.unlink()
after=shutil.disk_usage('.').free
out={'status':'PASS completed210 scopedAPI knownfixtures/rawduplicates removed after exactcase/critic/coreproof; laterUI app untouched','exactGithubMain':subprocess.check_output(['git','rev-parse','origin/main'],text=True).strip(),'exactProofPathCount':len(verified),'exactProofPaths':sorted(verified),'knownMovedFixturesRemoved':4,'rawFilesInMovedFixtures':41,'openFDsBeforeRemoval':0,'removedPaths':list(map(str,fixtures+raw_targets)),'appTerminationPerformed':False,'allocatedFileBytesRemoved':allocated,'availableBytesBefore':before,'availableBytesAfter':after,'observedFreeDeltaBytes':after-before,'positiveRecoveryCreditBytes':max(0,after-before),'scope':'Only exact4UUID movedfixtures+3completedcase rawbundles/logs/exports. Canonicalall3originalPNG/fullmetadata/fullappreports+all41fixturepayloads/nativefullsummaries/loggzip/sources/archives/audits/critics retained. LaterUIcurrentRoot/privatecopies/photos/defaults nothostdeleted. Raw/liveaudit paths historical aftercleanup; no userCancel or productionsafetyrepair credit. Immediate210native/package/purecaches,191video/skill/realwriterinputs, unrelatedprojects/sims/runtimes/userdata preserved. APFS/backgroundfreechanges mayaffectdelta; allocatedbytes separate.','checkedAt':time.time()};(p/'source210-root-api-cleanup-r1.json').write_text(json.dumps(out,indent=2)+'\n');print('Exactproofpaths',len(verified),'knownfixtures4/rawtargets9 removed; allocated',allocated,'B; observedfree delta',after-before)
