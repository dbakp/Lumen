"""Actual host transport OS publication, bounds, nofollow and post-publication failure controls."""
from pathlib import Path
import hashlib,importlib.util,json,os,tempfile,time
B=Path(__file__).resolve().parent;p=B/'retained-backend-transport-r1.py';before=p.read_bytes();output=B/'source261-transport-controls-r1.json';assert not output.exists()
spec=importlib.util.spec_from_file_location('transport',p);t=importlib.util.module_from_spec(spec);spec.loader.exec_module(t);checks=[]
with tempfile.TemporaryDirectory(prefix='lumen261-transport-') as temporary:
 root=Path(temporary).resolve();payload=b'{"synthetic":"ack"}'
 value=t.write_once(root,'ack.json',payload);assert value['status']=='SUPPORTED exclusive durable publication';checks.append({'case':'actual Darwin exclusive publish/fsync/readback','result':value})
 value=t.write_once(root,'ack.json',b'changed');assert value['status']=='FAILED publication' and value['published'] is False and (root/'ack.json').read_bytes()==payload;checks.append({'case':'existing ack never overwritten','result':value})
 (root/'link.json').symlink_to(root/'ack.json');value=t.read(root,'link.json');assert value['status']=='FAILED read';checks.append({'case':'symlink nofollow','result':value})
 os.mkfifo(root/'fifo.json');value=t.read(root,'fifo.json');assert value['status']=='FAILED read';checks.append({'case':'FIFO rejected before nonblocking read','result':value})
 os.link(root/'ack.json',root/'linked.json');value=t.read(root,'linked.json');assert value['status']=='FAILED read';checks.append({'case':'hardlinked ack rejected','result':value});(root/'linked.json').unlink()
 value=t.read(root,'missing.json');assert value['status']=='ABSENT anchored leaf';checks.append({'case':'actual pinned-parent leaf absence','result':value})
 value=t.read(root/'missing-parent','missing.json');assert value['status']=='FAILED read';checks.append({'case':'missing ancestor not leaf absence','result':value})
 for n in range(5):(root/('marker-'+str(n))).touch()
 value=t.list_names(root,'marker-',max_matched=3);assert value['status']=='FAILED inventory' and len(value['names'])==4 and value['overflow'];checks.append({'case':'matching cap plus one sentinel','result':value})
 value=t.list_names(root,'none-',max_scanned=3);assert value['status']=='FAILED inventory' and value['scannedAtLeast']==4 and value['overflow'];checks.append({'case':'scanning cap plus one sentinel','result':value})
 original=os.fsync;count=[0]
 def failed_directory(fd):
  count[0]+=1
  if count[0]==2:raise OSError('Synthetic actual callback fault after rename')
  return original(fd)
 os.fsync=failed_directory
 try:value=t.write_once(root,'post-publication-error.json',payload)
 finally:os.fsync=original
 assert value['status']=='FAILED publication' and value['published'] is True and value['mayHaveBeenObserved'] is True and value['readback']['raw']==t.blob(payload)
 checks.append({'case':'post-publication fsync failure retained may-be-observed, no blocked-Recover promise','result':value})
assert p.read_bytes()==before
result={'status':'PASS actual runner transport synthetic OS controls','helperBytes':len(before),'helperSHA256':hashlib.sha256(before).hexdigest(),'sourceBeforeAfterExact':True,'checks':checks,'temporarySyntheticFixturesRemoved':True,'scope':'Real host-only synthetic files and Darwin exclusive rename, named fsync callback fault. No native Recover or app/backend acceptance; no general process/global FD guarantee.','checkedAt':time.time()};output.write_text(json.dumps(result,indent=2)+'\n');print(len(checks),'transport OS controls passed')
