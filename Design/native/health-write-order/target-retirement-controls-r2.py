"""Task-owned temporary descriptor checks plus injected bounded-clock controls."""
import base64,copy,gzip,hashlib,importlib.util,json,os,shutil,tempfile,time
from pathlib import Path
from types import SimpleNamespace
from uuid import UUID
B=Path(__file__).resolve().parent
def module(name,file):
 s=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
r=module('retirement_under_test','legacy-target-retirement-r1.py');s=module('fresh_success_final','legacy-target-fresh-success-r2.py');v=module('tree_for_retirement','legacy-target-change-validation-r3.py')
h=SimpleNamespace(sha=lambda raw:hashlib.sha256(raw).hexdigest(),DATA=b'{synthetic persisted legacy origin damaged')
h.row=lambda raw:{'bytes':len(raw),'sha256':h.sha(raw),'base64':base64.b64encode(raw).decode()}
archive=(B/'source233-fresh-success-controls-r2-fixtures.json.gz').read_bytes();f=json.loads(gzip.decompress(archive))
first=copy.deepcopy(f['first']);baseline=copy.deepcopy(f['cases'][0]['record']);provider=f['provider'];start=f['started']
checks=[];captures=[]
def fd_set():
 result=set()
 for fd in range(1024):
  try:os.fstat(fd);result.add(fd)
  except OSError as error:
   assert error.errno==9
 return result
def test(name,action,accept=True):
 before_fds=fd_set()
 try:value=action();actual=True;error=None
 except Exception as e:value=None;actual=False;error=type(e).__name__
 assert fd_set()==before_fds,('descriptor leak',name)
 assert actual is accept,(name,actual,error)
 checks.append({'name':name,'accepted':actual,'expectedAcceptance':accept,'errorType':error});return value
def namespace(group,first,current,validation):
 out={};captures.append({'first':copy.deepcopy(first),'current':copy.deepcopy(current),'validation':copy.deepcopy(validation),'namespace':out})
 try:
  r.collect(group,out,first,current,validation,h,lambda:None)
  r.validate_namespace(out,first,current,validation,h)
 except Exception as e:out['controlErrorType']=type(e).__name__;raise
 return out
def meta(tree,name,identity):
 tree['metadata']['files'][name]['identity']=copy.deepcopy(identity)
 for row in tree['entries']:
  if row['path']==name:row['identity']=copy.deepcopy(identity)
with tempfile.TemporaryDirectory(prefix='LumenTargetRetirement233-') as temporary:
 group=Path(temporary)/'group';group.mkdir();retired=group/('LumenData.retired-'+str(UUID(int=90)));retired.mkdir()
 data=s.validate_payloads(baseline,first,provider,h,v,start)
 files,metadata,dirs=r.expected(first,baseline['current'],data)
 for name,row in files.items():
  path=retired/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(base64.b64decode(row['base64'],validate=True))
 first['current']['rootIdentity']=r.facts(retired.stat());baseline['current']['rootIdentity']['st_ino']=retired.stat().st_ino+100
 for name in files:
  identity=r.facts((retired/name).stat())
  if name in first['current']['files']:
   meta(first['current'],name,identity)
   if name!='health-write-intent.json':meta(baseline['current'],name,identity)
  else:meta(baseline['current'],name,identity)
 baseline['group']=str(group);baseline['namespace'].update(group=str(group),previous={'path':str(group/'LumenData.previous'),'exists':False,'errno':2})
 data=s.validate_payloads(baseline,first,provider,h,v,start)
 current=baseline['current']
 full=test('actual no-follow descriptor read of all17 retiring files',lambda:namespace(group,first,current,data))
 assert len([entry for entry in full['retired'][0]['entries'] if entry['kind']=='regular'])==17
 for label,fail_at in [('root initial persistence closes fd',2),('child entry persistence closes both fds',3)]:
  def failing_read():
   count=[0];sink={};captures.append({'persistFailure':label,'namespace':sink})
   def persist():
    count[0]+=1
    if count[0]>=fail_at:raise OSError('injected persistent writer failure')
   r.read_retiring(retired,sink,first,current,data,h,persist)
  test(label,failing_read,False)

 test('pending retired root is not settled success',lambda:s.validate({**baseline,'namespace':full},first,provider,h,v,start),False)
 wrong=copy.deepcopy(first);wrong['current']['rootIdentity']['st_ino']+=1
 test('wrong retired root inode rejected',lambda:namespace(group,wrong,current,data),False)
 leaf=retired/'chat.json';original=leaf.read_bytes();originalstat=leaf.stat()
 def restore_leaf():
  leaf.write_bytes(original);os.utime(leaf,ns=(originalstat.st_atime_ns,originalstat.st_mtime_ns))
 leaf.write_bytes(b'changed retired content')
 test('mutated still-present retiring file rejected',lambda:namespace(group,first,current,data),False);restore_leaf()
 leaf.unlink();leaf.symlink_to(Path(temporary)/'outside-unread')
 test('retiring leaf symlink rejected without following',lambda:namespace(group,first,current,data),False)
 leaf.unlink();leaf.write_bytes(original);identity=r.facts(leaf.stat());meta(first['current'],'chat.json',identity);meta(current,'chat.json',identity)
 unexpected=retired/'unreviewed';unexpected.write_bytes(b'unknown')
 test('unexpected retiring child rejected',lambda:namespace(group,first,current,data),False);unexpected.unlink()
 second=group/('LumenData.retired-'+str(UUID(int=91)));second.mkdir()
 test('extra retiring root rejected',lambda:namespace(group,first,current,data),False);second.rmdir()
 stage=group/'LumenData.restore-unexpected';stage.mkdir()
 test('unexpected stage retained and rejected',lambda:namespace(group,first,current,data),False);stage.rmdir()
 reset=group/'Lumen-reset-fixture-unexpected';reset.mkdir()
 test('unexpected reset fixture retained and rejected',lambda:namespace(group,first,current,data),False);reset.rmdir()
 invalid=group/'LumenData.retired-invalid';retired.rename(invalid)
 test('invalid retiring root UUID rejected',lambda:namespace(group,first,current,data),False);invalid.rename(retired)
 hidden=Path(temporary)/'held-known-root';retired.rename(hidden);retired.symlink_to(hidden,target_is_directory=True)
 test('retired root symlink rejected without following',lambda:namespace(group,first,current,data),False);retired.unlink();hidden.rename(retired)
 held=copy.deepcopy(first);held['current']['rootIdentity']['st_dev']+=1
 test('wrong retired device rejected',lambda:namespace(group,held,current,data),False)
 # Removing one known synthetic leaf models a partial asynchronous removal.
 leaf.unlink();partial=test('known partial retirement remains pending',lambda:namespace(group,first,current,data));assert not r.settled(partial)
 shutil.rmtree(retired)
 absent=test('actual ENOENT previous and retired namespace settled',lambda:namespace(group,first,current,data));assert r.settled(absent)
 test('strict success accepts real absent namespace',lambda:s.validate({**baseline,'namespace':absent},first,provider,h,v,start))
 # Inject a query error before traversal: never silently classify it as absent.
 original_open=r.os.open
 def denied(path,*args,**kwargs):raise PermissionError(13,'injected own fixture')
 r.os.open=denied
 try:test('permission query error is not absence',lambda:namespace(group,first,current,data),False)
 finally:r.os.open=original_open
 clock=[0.0]
 def clock_fn():return clock[0]
 def sleep_fn(seconds):clock[0]+=seconds
 def waiting(name,sequence,accept=True,cost=.01,persist_failure=False):
  clock[0]=0;out={};captures.append(out);calls=[0];writes=[0]
  def persist():
   writes[0]+=1
   if persist_failure and writes[0]>=4:raise OSError('injected outcome persistence failure')
  def sample(row):
   ordinal=calls[0];calls[0]+=1
   mode=sequence[min(ordinal,len(sequence)-1)]
   if mode=='error':raise PermissionError('injected observation failure')
   value=copy.deepcopy(baseline);value['namespace']=copy.deepcopy(partial if mode=='pending' else absent)
   row['success']=value
   s.validate_payloads(value,first,provider,h,v,start);r.validate_namespace(value['namespace'],first,value['current'],data,h)
   clock[0]+=cost
  test(name,lambda:r.wait(out,sample,persist,clock_fn,sleep_fn),accept)
  return out
 immediate=waiting('three settled samples accepted',['absent'])
 transition=waiting('known retirement then stable absence',['pending','absent'])
 waiting('pending retirement deadline fails',['pending'],False,3)
 waiting('observation failure retained and fails',['error'],False)
 waiting('persistence failure cannot pass',['absent'],False,persist_failure=True)
 waiting('completed sample over budget fails',['absent'],False,11)
 def validate_sample(row):
  value=row['success'];s.validate_payloads(value,first,provider,h,v,start);r.validate_namespace(value['namespace'],first,value['current'],data,h)
 test('retained immediate observations revalidated',lambda:r.validate_wait(immediate,validate_sample))
 test('retained transition observations revalidated',lambda:r.validate_wait(transition,validate_sample))
 for name,mutator in [
  ('forged settled label',lambda out:out['samples'][0].update(settled=True)),
  ('forged accepted elapsed',lambda out:out.update(acceptedElapsed=9)),
  ('missing stability samples',lambda out:out['samples'].pop()),
  ('changed sample budget',lambda out:out.update(budgetSeconds=20)),
  ('backward sample times',lambda out:out['samples'][1].update(elapsed=-1)),
  ('retained wrong retired inode',lambda out:out['samples'][0]['success']['namespace']['retired'][0]['identity'].update(st_ino=0))]:
  altered=copy.deepcopy(transition);mutator(altered)
  test(name,lambda:r.validate_wait(altered,validate_sample),False)
 # Records contain only synthetic fixture inputs and local-path metadata.
 decoded=json.dumps({'first':first,'baseline':baseline,'checks':checks,'captures':captures},sort_keys=True).encode()
 target=B/'source233-retirement-controls-r2-fixtures.json.gz';assert not target.exists();target.write_bytes(gzip.compress(decoded,mtime=0))
out={'status':'PASS isolated actual temporary descriptor and injected retirement controls','everyCheckOwnDescriptorSetPreserved':True,'count':len(checks),'accepted':sum(row['accepted'] for row in checks),'rejected':sum(not row['accepted'] for row in checks),'checks':checks,'sourceBaselineArchiveSHA256':h.sha(archive),'observerSHA256':h.sha((B/'legacy-target-retirement-r1.py').read_bytes()),'fixtureArchive':{'file':target.name,'bytes':target.stat().st_size,'sha256':h.sha(target.read_bytes()),'decodedBytes':len(decoded),'decodedSHA256':h.sha(decoded)},'scope':'Own temporary synthetic folder only, removed by TemporaryDirectory. Clock/query/write failures injected; no actual simulator/app/LocalStore/Health operation or actual product retirement timing proof.','checkedAt':time.time()}
(B/'source233-retirement-controls-r2.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps({key:value for key,value in out.items() if key!='checks'}))
