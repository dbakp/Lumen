"""Remove only backed, obsolete named Lumen raw results and isolated probes."""
from pathlib import Path
import base64,gzip,hashlib,json,os,shutil,stat,subprocess,time
repo=Path('/Users/davidbakposada/Documents/ChatGPT/Lumen');base=repo/'Design/native/health-write-order';sha=lambda d:hashlib.sha256(d).hexdigest()
old=json.loads(Path('/tmp/lumen-old161-raw-cleanup-proofs.json').read_text());current=json.loads(Path('/tmp/lumen215-mixed-publish-paths.json').read_text())
proofs=set(current)|{str(base.relative_to(repo)/name) for name in old['proofs']}|{str(base.relative_to(repo)/name) for name in ['durable-source-r215.json','durable-source-r215.json.gz','source215-mixed-harness-isolated-probes-r1-artifacts.json.gz','source215-mixed-harness-isolated-probes-r1.json','source215-mixed-harness-isolated-probes-r1-executed.py','source215-mixed-harness-isolated-probes-r1-root-review.json','health-legacy-mixed-ineligible-source215-round2-part76-source.json']}
# Batch Git object reads avoid spawning a separate process per old screenshot.
git=subprocess.Popen(['git','cat-file','--batch'],cwd=repo,stdin=subprocess.PIPE,stdout=subprocess.PIPE)
backup=[]
try:
 for name in sorted(proofs):
  p=repo/name;assert p.is_relative_to(repo) and not p.is_symlink() and '..' not in Path(name).parts
  data=p.read_bytes();git.stdin.write(('origin/main:'+name+'\n').encode());git.stdin.flush()
  fields=git.stdout.readline().split();assert len(fields)==3 and fields[1]==b'blob',name
  size=int(fields[2]);remote=git.stdout.read(size);assert git.stdout.read(1)==b'\n' and remote==data,name
  backup.append({'file':name,'bytes':len(data),'sha256':sha(data)})
finally:
 git.stdin.close();git.wait();assert git.returncode==0
raw43=Path('/tmp/LumenBatch43Checks');stem=old['stem'];raw44=Path('/tmp/LumenBatch44Checks');newstem='HealthMixedIneligibleSource215R1'
targets=[raw43/(stem+suffix) for suffix in ['.xcresult','PNG','JSON','.log','Driver.log','PNGExport.log','JSONExport.log','-summary.json']]+[raw44/(newstem+suffix) for suffix in ['.xcresult','PNG','JSON','.log','-summary.json']]+[Path('/tmp/LumenMixedHarnessProbe215R1')]
assert len(targets)==14 and len(set(targets))==14
# Old and new canonical attachment/native bytes must still equal their raw peers.
for prefix in [old['prefix'],'health-mixed-ineligible-source215r1']:
 for index in ['images','readbacks']:
  for row in json.loads((base/(prefix+'-'+index+'.json')).read_bytes()):
   assert (base/row['file']).read_bytes()==Path(row['raw']).read_bytes()
# Original manifest bytes were added and backed before this deletion.
for prefix,root,name in [(old['prefix'],raw43,stem),('health-mixed-ineligible-source215r1',raw44,newstem)]:
 for ext in ['png','json']:
  retained=base/(prefix+('-raw-original-' if prefix==old['prefix'] else '-')+ext+('-manifest.json.gz' if prefix==old['prefix'] else '-original-manifest.json.gz'))
  assert gzip.decompress(retained.read_bytes())==(root/(name+ext.upper())/'manifest.json').read_bytes()
# Full isolated probe archive, not merely its two representative peers.
archive=json.loads(gzip.decompress((base/'source215-mixed-harness-isolated-probes-r1-artifacts.json.gz').read_bytes()))
for name,row in archive['files'].items():
 data=(targets[-1]/name).read_bytes();assert data==base64.b64decode(row['base64'],validate=True) and len(data)==row['bytes'] and sha(data)==row['sha256']
ps=subprocess.check_output(['ps','-axo','pid,args'],text=True)
assert not any(('xcodebuild' in line or 'health-mixed-ineligible-driver' in line) and any(str(p) in line for p in targets) for line in ps.splitlines() if 'zsh -lc' not in line and 'python3 -' not in line)
allocated=0;regular=0;seen=set();inventory=[]
for target in targets:
 assert target.exists() and not target.is_symlink()
 files=[]
 if target.is_dir():
  for parent,dirs,names in os.walk(target,followlinks=False):
   for name in dirs:assert not (Path(parent)/name).is_symlink()
   files += [Path(parent)/name for name in names]
 else:files=[target]
 for p in files:
  facts=p.lstat();assert stat.S_ISREG(facts.st_mode) and not p.is_symlink()
  regular+=1
  if (facts.st_dev,facts.st_ino) not in seen:allocated+=facts.st_blocks*512;seen.add((facts.st_dev,facts.st_ino))
 scan=subprocess.run(['lsof','-nP','+D',str(target)] if target.is_dir() else ['lsof','-nP',str(target)],capture_output=True,text=True)
 assert scan.returncode==1 and not scan.stdout, 'Open files: '+str(target)
 inventory.append({'path':str(target),'regularFiles':len(files)})
before=shutil.disk_usage(repo).free
for target in targets:
 if target.is_dir():shutil.rmtree(target)
 else:target.unlink()
 assert not target.exists()
after=shutil.disk_usage(repo).free;credit=min(allocated,max(0,after-before))
r={'status':'PASS14namedobsolete raw/probe targets deleted after exactGitHub proofs; allcanonicalsource/originals/reports retained','exactGithubMain':subprocess.check_output(['git','rev-parse','origin/main'],cwd=repo,text=True).strip(),'exactBackupPaths':backup,'removed':inventory,'regularFiles':regular,'uniqueRegularAllocatedBytes':allocated,'availableBytesBefore':before,'availableBytesAfter':after,'observedFreeDeltaBytes':after-before,'positiveRecoveryCreditBytes':credit,'creditConvention':'Conservative min(allocated,positive observed volume free change); concurrent background volume usage may affect observed delta.','cases':'Historical superseded161149PNG/fullJSON + current21514PNG/full6482Bhelper/actualPASS+P77C1gap +isolated215mocked22artifactarchive remain canonical/backed. Historicalindexflags unchanged; no global/visual acceptance added.','retained':'Current216frozenrepo/old215evidence/skill/native+packagecaches for immediatebuild/realwriterinputs/Source191originalvideo103462585B andotherprojects/simulators/personaldata untouched. Current21518filetree/defaults unchanged, noreset. No cleanup-only build.','checkedAt':time.time()}
(base/'source216-obsolete-raw-cleanup-r1.json').write_text(json.dumps(r,indent=2)+'\n');(base/'source216-obsolete-raw-cleanup-r1-executed.py').write_bytes(Path(__file__).read_bytes());print(json.dumps({k:r[k] for k in ['status','regularFiles','uniqueRegularAllocatedBytes','observedFreeDeltaBytes','positiveRecoveryCreditBytes','availableBytesAfter']}),flush=True)
