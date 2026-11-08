"""Remove completed, backed-up Mac logic outputs only; preserve active iOS build."""
from pathlib import Path
import json,gzip,base64,hashlib,os,stat,subprocess,shutil,time
B=Path(__file__).resolve().parent;repo=B.parents[2];sha=lambda x:hashlib.sha256(x).hexdigest();proof=json.loads((B/'source244-prebuild-exact-github.json').read_bytes());assert proof['commit']=='756160570d1b7d1e53d89dfbf7931e6b5025b7c6' and proof['unionPaths']==1282;by={r['file']:r for r in proof['proofs']}
required=['durable-source-r244.json','durable-source-r244.json.gz','health-healthy-target-change-source244-round2-part146-source.json','source244-root-part146-review.json','source244-origin-review-r1-outcome.json','source244-logic-regressions-r1.json','source244-logic-synthetic-roots-r1.json','source244-logic-synthetic-roots-r1.json.gz']
for name in required:
 p=B/name;data=p.read_bytes();r=by[str(p.relative_to(repo))];assert len(data)==r['bytes'] and sha(data)==r['sha256'] and not p.is_symlink()
fixture=json.loads((B/'source244-logic-synthetic-roots-r1.json').read_bytes());raw=gzip.decompress((B/fixture['fixture']).read_bytes());assert len(raw)==fixture['decodedBytes'] and sha(raw)==fixture['decodedSHA256'];roots=json.loads(raw)['roots']
for root,record in roots.items():
 root=Path(root);assert not root.is_symlink()
 for row in record['entries']:
  p=root/row['path'];s=p.lstat();assert all(getattr(s,k)==v for k,v in row['identity'].items())
  if row['kind']=='regular':assert p.read_bytes()==base64.b64decode(row['base64'],validate=True)
  elif row['kind']=='symlink':assert os.readlink(p)==row['target']
cache=Path('/tmp/LumenLogicBuild');assert cache.is_dir() and not cache.is_symlink();targets=[cache]+[Path(p) for p in roots]
rawbase=Path('/tmp/LumenBatch44Checks')
for stem in ['Source244OriginReviewR1']+['Source244Logic-'+n+'R1' for n in ['full','legacy-origin','legacy-transaction','legacy-boundaries']]:
 for ext in ['.log','.json']:
  p=rawbase/(stem+ext)
  if p.exists():assert not p.is_symlink() and p.is_file();targets.append(p)
allocated=0;regular=0;links=0;rows=[]
for root in targets:
 paths=[root]
 if root.is_dir():
  for parent,dirs,names in os.walk(root,followlinks=False):paths.extend(Path(parent)/n for n in dirs+names)
 subtotal=0
 for p in paths:
  s=p.lstat();assert stat.S_ISREG(s.st_mode) or stat.S_ISDIR(s.st_mode) or stat.S_ISLNK(s.st_mode)
  if stat.S_ISREG(s.st_mode):regular+=1;subtotal+=s.st_blocks*512
  elif stat.S_ISLNK(s.st_mode):links+=1
 allocated+=subtotal;rows.append({'path':str(root),'allocatedRegularBytes':subtotal})
out={'status':'PREPARED exact1282backed completedMaclogic-only cleanup','proofCommit':proof['commit'],'proofUnion':1282,'targets':rows,'regularFiles':regular,'symlinksNotFollowed':links,'allocatedRegularBytes':allocated,'deleted':[],'started':time.time()};output=B/'source244-completed-logic-cleanup-r1.json';assert not output.exists()
def persist():output.write_text(json.dumps(out,indent=2)+'\n')
persist()
# Inspect arguments in memory only, retaining no unrelated process arguments.
query=subprocess.run(['ps','-axo','pid=,args='],capture_output=True,text=True);assert query.returncode==0;active=[]
for line in query.stdout.splitlines():
 parts=line.strip().split(None,1)
 if len(parts)==2 and '/tmp/LumenLogicBuild' in parts[1]:active.append(int(parts[0]))
out['activeMacScratchProcessPIDs']=active;persist();assert not active
before=shutil.disk_usage(repo).free;out['beforeAvailableBytes']=before;persist()
for path in targets:
 assert not path.is_symlink()
 if path.is_dir():shutil.rmtree(path)
 else:path.unlink()
 assert not os.path.lexists(path);out['deleted'].append(str(path));persist()
after=shutil.disk_usage(repo).free;credit=min(allocated,max(0,after-before));out.update(status='PASS backed completedMaclogicbuild/4knownsyntheticroots/rawMacduplicates removed; activeiOSDebug/packages/provider/canonicaloutcomes/skill/unbacked191219 preserved',afterAvailableBytes=after,observedAvailableIncrease=after-before,creditedRecoveryBytes=credit,aggregateCreditedRecoveryBytes=12981988951+credit,finished=time.time());persist();print(json.dumps({k:out[k] for k in ['regularFiles','symlinksNotFollowed','allocatedRegularBytes','observedAvailableIncrease','creditedRecoveryBytes','aggregateCreditedRecoveryBytes','afterAvailableBytes']}))
