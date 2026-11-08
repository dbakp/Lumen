"""Remove only backed-up isolated synthetic bootstrap fixture duplicates."""
from pathlib import Path
import json,gzip,base64,hashlib,os,stat,shutil,tempfile,time
b=Path('Design/native/health-write-order');proof=json.loads((b/'source230-preexecution-exact-github.json').read_text());by={r['file']:r for r in proof['proofs']};assert proof['commit']=='d9c539d8fcbfc4ef738756a4c225c8915595f8f2'
plan=json.loads((b/'source230-target-change-bootstrap-r1-plan.json').read_text());report=json.loads((b/'source230-bootstrap-controls-r1.json').read_text())
for path in [b/'source230-target-change-bootstrap-r1-plan.json',b/'source230-bootstrap-controls-r1.json',b/report['fixtureArchive'],b/'target-bootstrap-controls-r1.py']:
 data=path.read_bytes();want=by[str(path)];assert len(data)==want['bytes'] and hashlib.sha256(data).hexdigest()==want['sha256']
fixture=json.loads(gzip.decompress((b/report['fixtureArchive']).read_bytes()));known=[base64.b64decode(v,validate=True) for v in fixture['rawPlists'].values() if type(v) is str]
cases={r['case'] for r in report['cases'] if r['kind']=='actual isolated observer'}
roots=[Path(x) for x in plan['rawFixtureRootsRetained']];rows=[];allocated=0;files=0;links=0
for root in roots:
 assert root.parent==Path(tempfile.gettempdir()) and root.name.startswith('LumenTargetBootstrap230-') and root.is_dir() and not root.is_symlink()
 for parent,dirs,names in os.walk(root,followlinks=False):
  for name in dirs:
   child=Path(parent)/name;assert child.parent==root and name in cases and not child.is_symlink()
  for name in names:
   path=Path(parent)/name;assert path.parent.parent==root and path.parent.name in cases
   facts=path.lstat();row={'file':str(path),'mode':facts.st_mode,'bytes':facts.st_size}
   if stat.S_ISLNK(facts.st_mode):
    assert path.parent.name=='symlink' and name=='com.dbakp.lumen.plist' and os.readlink(path)=='known-target.plist'
    row.update(kind='known rejected synthetic link',target=os.readlink(path));links+=1
   else:
    assert stat.S_ISREG(facts.st_mode) and facts.st_size<=512*1024 and name in ['com.dbakp.lumen.plist','known-target.plist']
    data=path.read_bytes();assert data in known or (path.parent.name=='identity-race' and data.endswith(b'\n') and data[:-1] in known)
    row.update(kind='known synthetic fixture',sha256=hashlib.sha256(data).hexdigest(),allocatedBytes=facts.st_blocks*512)
    allocated+=facts.st_blocks*512;files+=1
   rows.append(row)
outpath=b/'source230-isolated-bootstrap-raw-cleanup-r1.json';assert not outpath.exists();before=shutil.disk_usage('.').free
out={'status':'PREPARED exact-backed synthetic raw duplicate cleanup','proofCommit':proof['commit'],'proofUnion':proof['unionPaths'],'roots':[str(p) for p in roots],'entries':rows,'regularFiles':files,'knownRejectedLinks':links,'allocatedRegularBytes':allocated,'beforeAvailableBytes':before,'deleted':[],'started':time.time()}
def persist():outpath.write_text(json.dumps(out,indent=2)+'\n')
persist()
for root in roots:shutil.rmtree(root);out['deleted'].append(str(root));persist()
after=shutil.disk_usage('.').free;credit=min(allocated,max(0,after-before));out.update(status='PASS only isolated backed-up synthetic raw fixtures removed; no link followed',afterAvailableBytes=after,observedAvailableIncrease=after-before,creditedRecoveryBytes=credit,aggregateCreditedRecoveryBytes=10171252311+credit,finished=time.time());persist();print(json.dumps({k:out[k] for k in ['regularFiles','knownRejectedLinks','creditedRecoveryBytes','aggregateCreditedRecoveryBytes']}))
