"""Delete only exact-backed failed216 raw duplicates and finished media cache."""
from pathlib import Path
import json,gzip,base64,hashlib,os,stat,shutil,subprocess,time
repo=Path('/Users/davidbakposada/Documents/ChatGPT/Lumen');b=repo/'Design/native/health-write-order';sha=lambda d:hashlib.sha256(d).hexdigest();names=json.loads(Path('/tmp/lumen216-failure-publish-paths.json').read_text())
# Include the unchanged extractor itself and frozen source/archive too.
names=sorted(set(names+['scripts/extract-verification-frames.swift',str(b.relative_to(repo)/'durable-source-r216.json'),str(b.relative_to(repo)/'durable-source-r216.json.gz')]))
proofs=[]
for name in names:
 data=(repo/name).read_bytes();assert not (repo/name).is_symlink();assert subprocess.check_output(['git','show','origin/main:'+name],cwd=repo)==data,name;proofs.append({'file':name,'bytes':len(data),'sha256':sha(data)})
raw=Path('/tmp/LumenBatch44Checks');stem='HealthMixedIneligibleSource216R1';prefix='health-mixed-ineligible-source216r1'
for r in json.loads((b/(prefix+'-images.json')).read_text()):assert (b/r['file']).read_bytes()==Path(r['raw']).read_bytes()
assert json.loads((b/(prefix+'-readbacks.json')).read_text())==[]
archive=json.loads(gzip.decompress((b/(prefix+'-all-nonvideo-attachments.json.gz')).read_bytes()));allroot=raw/(stem+'AllAttachments')
for name,r in archive['files'].items():
 data=(allroot/name).read_bytes();assert data==base64.b64decode(r['base64'],validate=True) and len(data)==r['bytes'] and sha(data)==r['sha256']
manifest=gzip.decompress((b/(prefix+'-all-original-manifest.json.gz')).read_bytes());assert (allroot/'manifest.json').read_bytes()==manifest
video=b/(prefix+'-native-failure-recording.mp4');assert video.read_bytes()==(allroot/'BFE00895-DD4F-43E2-9310-D5729FDD2477.mp4').read_bytes()
frames=raw/(stem+'FailureFrames');assert (b/'source216-failure-video-frame-provenance.json').read_bytes()==(frames/'frame-provenance.json').read_bytes()
for row in json.loads((frames/'frame-provenance.json').read_text())['frames']:assert (frames/row['file']).read_bytes()==(b/(prefix+'-video-'+row['file'])).read_bytes()
targets=[raw/(stem+s) for s in ['.xcresult','PNG','JSON','.log','-summary.json','AllAttachments','FailureFrames']]+[Path('/tmp/LumenVerificationVideoModuleCache')]
assert len(targets)==8
ps=subprocess.check_output(['ps','-axo','pid,args'],text=True)
assert not any(('xcodebuild' in line or 'swift' in line) and any(str(p) in line for p in targets) for line in ps.splitlines() if 'zsh -lc' not in line and 'python3 -' not in line)
allocated=0;regular=0;links=0;seen=set();inventory=[]
for target in targets:
 assert target.exists() and not target.is_symlink()
 files=[]
 if target.is_dir():
  for parent,dirs,names1 in os.walk(target,followlinks=False):
   for name in dirs:
    child=Path(parent)/name
    if child.is_symlink():links+=1;dirs.remove(name)
   files += [Path(parent)/name for name in names1]
 else:files=[target]
 for p in files:
  f=p.lstat()
  if stat.S_ISLNK(f.st_mode):links+=1;continue
  assert stat.S_ISREG(f.st_mode);regular+=1
  if (f.st_dev,f.st_ino) not in seen:allocated+=f.st_blocks*512;seen.add((f.st_dev,f.st_ino))
 scan=subprocess.run(['lsof','-nP','+D',str(target)] if target.is_dir() else ['lsof','-nP',str(target)],capture_output=True,text=True)
 assert scan.returncode==1 and not scan.stdout,'Open taskdata '+str(target)
 inventory.append({'path':str(target),'regularEntries':len(files)})
before=shutil.disk_usage(repo).free
for target in targets:
 if target.is_dir():shutil.rmtree(target)
 else:target.unlink()
 assert not target.exists()
after=shutil.disk_usage(repo).free;credit=min(allocated,max(0,after-before))
r={'status':'PASS8named obsolete216failedraw/media-cache targets removed after exactbackups; current217source/nativecache andfailedsandboxstate untouched','exactGithubMain':subprocess.check_output(['git','rev-parse','origin/main'],cwd=repo,text=True).strip(),'exactBackupPaths':proofs,'removed':inventory,'regularFiles':regular,'symlinksRemovedWithoutFollowing':links,'uniqueAllocatedRegularBytes':allocated,'availableBytesBefore':before,'availableBytesAfter':after,'observedFreeDeltaBytes':after-before,'positiveRecoveryCreditBytes':credit,'creditConvention':'min(positive observed volume free change,allocated), other volume users mayaffectdelta','preserved':'Actual216failed0/1/0/source/fullsummary/3originals/0helper/57payloadarchive/58manifest/native38484747Bvideo/2derivedframes/fullreports keptcanonical+GitHub. Raw/tmpreferences historical now. No inventedfailedhelper/14counts/success. Current217frozen code+native/packagecaches for immediatecompile, app current/prior10/10 andownedsourceworkspaces untouched; skill/realinputs/191unbackedvideo/otherprojects/simulators/personaldata preserved. No cleanup-onlybuild.','checkedAt':time.time()}
(b/'source217-failed-raw-media-cleanup-r1.json').write_text(json.dumps(r,indent=2)+'\n');(b/'source217-failed-raw-media-cleanup-r1-executed.py').write_bytes(Path(__file__).read_bytes());print(json.dumps({k:r[k] for k in ['status','regularFiles','symlinksRemovedWithoutFollowing','uniqueAllocatedRegularBytes','observedFreeDeltaBytes','positiveRecoveryCreditBytes','availableBytesAfter']}),flush=True)
