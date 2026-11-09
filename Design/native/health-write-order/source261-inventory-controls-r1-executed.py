"""Actual metadata-only inventory controls; no simulator access."""
from pathlib import Path
import hashlib,importlib.util,json,os,tempfile,time
B=Path(__file__).resolve().parent;p=B/'retained-backend-inventory-r1.py';before=p.read_bytes();output=B/'source261-inventory-controls-r1.json';assert not output.exists()
spec=importlib.util.spec_from_file_location('inventory',p);i=importlib.util.module_from_spec(spec);spec.loader.exec_module(i);checks=[]
with tempfile.TemporaryDirectory(prefix='lumen261-inventory-') as temporary:
 root=Path(temporary).resolve();(root/'LumenData').mkdir();(root/'LumenData.previous').mkdir();(root/'unrelated.txt').write_bytes(b'Not read by inventory')
 value=i.inventory(root);assert value['status'].startswith('SUPPORTED') and set(value['entries'])=={'LumenData','LumenData.previous'};checks.append({'case':'bounded owned namespace excludes unrelated files','sample':value})
 outside=root/'outside';outside.mkdir();(root/'LumenData.link').symlink_to(outside,target_is_directory=True);value=i.inventory(root);assert value['status']=='FAILED namespace inventory';checks.append({'case':'namespace symlink rejected without traversal','sample':value});(root/'LumenData.link').unlink()
 alias=root/'alias';alias.symlink_to(root,target_is_directory=True);value=i.inventory(alias);assert value['status']=='FAILED namespace inventory';checks.append({'case':'ancestor symlink rejected','sample':value})
 original=os.listdir;once=[False]
 def changed(fd):
  names=original(fd)
  if not once[0]:once[0]=True;(root/'LumenData.restore-synthetic').mkdir()
  return names
 os.listdir=changed
 try:value=i.inventory(root)
 finally:os.listdir=original
 assert value['status']=='FAILED namespace inventory';checks.append({'case':'actual sibling inventory mutation rejected','sample':value})
assert p.read_bytes()==before
result={'status':'PASS actual task namespace metadata inventory controls','helperBytes':len(before),'helperSHA256':hashlib.sha256(before).hexdigest(),'sourceBeforeAfterExact':True,'checks':checks,'temporarySyntheticFixturesRemoved':True,'scope':'Metadata of synthetic task-prefixed sibling paths only, unrelated file contents never read. No app/native/global descriptor acceptance.','checkedAt':time.time()};output.write_text(json.dumps(result,indent=2)+'\n');print(len(checks),'inventory controls passed')
