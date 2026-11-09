"""Actual sampler controls over tiny synthetic OS files; retain all failed samples."""
from pathlib import Path
import base64, gzip, hashlib, importlib.util, json, os, tempfile, time
B=Path(__file__).resolve().parent;output=B/'source261-snapshot-controls-r2.json';rawout=B/'source261-snapshot-controls-r2-raw.json.gz'
assert not output.exists() and not rawout.exists()
source=B/'retained-backend-snapshot-r2.py';before=source.read_bytes()
spec=importlib.util.spec_from_file_location('snapshot',source);s=importlib.util.module_from_spec(spec);spec.loader.exec_module(s)
checks=[];samples={}
with tempfile.TemporaryDirectory(prefix='lumen261-snapshot-') as temporary:
 root=Path(temporary).resolve();outside=root/'outside';outside.write_bytes(b'SYNTHETIC-NO-FOLLOW-CANARY')
 def area(name):
  folder=root/name;folder.mkdir();(folder/'a.bin').write_bytes(b'alpha');(folder/'z-peer.bin').write_bytes(b'peer');return folder
 def verify(name,roots,accept,canary=False):
  value=s.capture(roots);samples[name]=value;assert value['status'].startswith('SUPPORTED')==accept,name
  if canary:
   for label in roots:
    assert all(base64.b64decode(row['raw']['base64'])!=outside.read_bytes() for row in s.files(value,label).values()),name
  checks.append({'case':name,'supported':accept,'errors':len(value['errors'])});return value
 regular=area('regular');(regular/'nested').mkdir();(regular/'nested'/'b.bin').write_bytes(bytes([0,255,17]));os.link(regular/'a.bin',regular/'linked.bin')
 value=verify('regular nested hardlinks and absent',{'current':regular,'absent':root/'not-present'},True)
 assert value['roots']['absent']['absent'] is True and value['roots']['absent']['ancestorPathBindings']
 verify('missing intermediate fails closed',{'unsafe':root/'missing-parent'/'file','peer':regular/'z-peer.bin'},False)
 assert s.files(value,'current')['a.bin']['identityBefore']['st_nlink']==2
 assert s.files(value,'current')['a.bin']['raw']==s.files(value,'current')['linked.bin']['raw']
 alias=root/'alias';alias.symlink_to(regular,target_is_directory=True)
 verify('root symlink nofollow',{'unsafe':alias,'peer':regular/'z-peer.bin'},False,True)
 verify('intermediate symlink nofollow',{'unsafe':alias/'a.bin','peer':regular/'z-peer.bin'},False,True)
 dangling=root/'dangling';dangling.symlink_to(root/'missing-target');verify('dangling symlink rejected',{'unsafe':dangling},False)
 fifo=area('fifo');os.mkfifo(fifo/'fifo.bin');v=verify('fifo never read and later peer retained',{'current':fifo},False,True);assert s.files(v,'current')['z-peer.bin']['raw']['bytes']==4
 deep=area('deep');path=deep
 for i in range(15):path=path/str(i);path.mkdir()
 verify('depth bound and regular peer',{'current':deep},False)
 big=area('oversize')
 with (big/'too-large.bin').open('wb') as stream:stream.truncate(s.MAX_FILE+1)
 v=verify('actual file size limit before read',{'current':big},False);assert s.files(v,'current')['z-peer.bin']['raw']['bytes']==4
 crowded=root/'crowded';crowded.mkdir()
 for i in range(s.MAX_ENTRIES+1):(crowded/str(i)).touch()
 v=verify('actual directory entry bound with independent peer',{'crowded':crowded,'peer':regular/'z-peer.bin'},False)
 inventory=v['roots']['crowded']['inventoryBefore'];assert inventory['overflow'] is True and len(inventory['names'])<=s.MAX_ENTRIES and inventory['observedAtLeast']==inventory['limit']+1
 assert s.files(v,'peer')['']['raw']['bytes']==4
 changed=area('read-mutation');original_read=os.read;once=[False]
 def mutate_read(fd,count):
  data=original_read(fd,count)
  if data and not once[0]:
   once[0]=True
   with (changed/'a.bin').open('ab') as stream:stream.write(b'changed')
  return data
 os.read=mutate_read
 try:v=verify('real in-place mutation retained rejected',{'current':changed},False)
 finally:os.read=original_read
 assert 'raw' in v['roots']['current']['children']['a.bin']
 listing=area('inventory-mutation');original_scan=os.scandir;once=[False]
 class MutatingScan:
  def __init__(self,fd):self.entries=original_scan(fd)
  def __enter__(self):return self
  def __exit__(self,*args):self.entries.close()
  def __iter__(self):return self
  def __next__(self):
   value=next(self.entries)
   if not once[0]:once[0]=True;(listing/'new.bin').write_bytes(b'new')
   return value
 os.scandir=MutatingScan
 try:verify('real directory inventory mutation rejected',{'current':listing},False)
 finally:os.scandir=original_scan
 swap=area('nofollow-swap');original_open=os.open;once=[False]
 def swapped_open(name,flags,*args,**kwargs):
  if name=='a.bin' and kwargs.get('dir_fd') is not None and not once[0]:
   once[0]=True;(swap/'a.bin').unlink();(swap/'a.bin').symlink_to(outside)
  return original_open(name,flags,*args,**kwargs)
 os.open=swapped_open
 try:verify('real regular-to-symlink swap nofollow',{'current':swap},False,True)
 finally:os.open=original_open
 bounded=area('aggregate');(bounded/'a.bin').write_bytes(b'0123456789');(bounded/'z-peer.bin').write_bytes(b'0123456789');limit=s.MAX_TOTAL;s.MAX_TOTAL=16
 try:verify('actual aggregate counter under named small injected limit',{'current':bounded},False)
 finally:s.MAX_TOTAL=limit
 assert not [p for p in root.iterdir() if p.name.startswith('user')]
after=source.read_bytes();assert before==after
raw=json.dumps({'samples':samples,'scope':'Real tiny temporary synthetic OS fixtures; named small aggregate budget injection and real OS mutation hooks. No native simulator/app/backend acceptance.'},sort_keys=True).encode();rawout.write_bytes(gzip.compress(raw,mtime=0))
result={'status':'PASS actual bounded nofollow sampler synthetic OS controls','sourceBytes':len(before),'sourceSHA256':hashlib.sha256(before).hexdigest(),'sourceBeforeAfterExact':True,'checks':checks,'raw':rawout.name,'rawDecodedBytes':len(raw),'rawDecodedSHA256':hashlib.sha256(raw).hexdigest(),'syntheticTemporaryFixturesRemoved':True,'scope':'Actual sampler with OS regular/directory/hardlink/symlink/FIFO/mutation/size/inventory bounds. No global FD/atomic/continuous or app acceptance; all failed sample diagnostics retained.','checkedAt':time.time()};output.write_text(json.dumps(result,indent=2)+'\n');print(len(checks),'actual sampler controls passed')
