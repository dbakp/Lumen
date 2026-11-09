"""Actual metadata-only inventory controls; no simulator access."""
from pathlib import Path
import hashlib,importlib.util,json,os,tempfile,time
B=Path(__file__).resolve().parent;p=B/'retained-backend-inventory-r2.py';before=p.read_bytes();output=B/'source261-inventory-controls-r2.json';assert not output.exists()
spec=importlib.util.spec_from_file_location('inventory',p);i=importlib.util.module_from_spec(spec);spec.loader.exec_module(i);checks=[]
with tempfile.TemporaryDirectory(prefix='lumen261-inventory-') as temporary:
 root=Path(temporary).resolve();(root/'LumenData').mkdir();(root/'LumenData.previous').mkdir();(root/'unrelated.txt').write_bytes(b'Not read by inventory')
 value=i.inventory(root);assert value['status'].startswith('SUPPORTED') and set(value['entries'])=={'LumenData','LumenData.previous'};checks.append({'case':'bounded owned namespace excludes unrelated files','sample':value})
 outside=root/'outside';outside.mkdir();(root/'LumenData.link').symlink_to(outside,target_is_directory=True);value=i.inventory(root);assert value['status']=='FAILED namespace inventory';checks.append({'case':'namespace symlink rejected without traversal','sample':value});(root/'LumenData.link').unlink()
 alias=root/'alias';alias.symlink_to(root,target_is_directory=True);value=i.inventory(alias);assert value['status']=='FAILED namespace inventory';checks.append({'case':'ancestor symlink rejected','sample':value})
 original=os.scandir;once=[False]
 class MutatingScan:
  def __init__(self,fd):self.entries=original(fd)
  def __enter__(self):return self
  def __exit__(self,*args):self.entries.close()
  def __iter__(self):return self
  def __next__(self):
   value=next(self.entries)
   if not once[0]:once[0]=True;(root/'LumenData.restore-synthetic').mkdir()
   return value
 os.scandir=MutatingScan
 try:value=i.inventory(root)
 finally:os.scandir=original
 assert value['status']=='FAILED namespace inventory';checks.append({'case':'actual sibling inventory mutation rejected','sample':value})
 crowded=root/'crowded';crowded.mkdir()
 for n in range(34):(crowded/('LumenData.synthetic-'+str(n))).mkdir()
 value=i.inventory(crowded);assert value['status']=='FAILED namespace inventory'
 assert value['inventoryBefore']['overflow'] is True and len(value['namesBefore'])==33
 checks.append({'case':'matching names capped at32plus sentinel','sample':value})
 many=root/'unrelated-crowded';many.mkdir()
 for n in range(2050):(many/('unrelated-'+str(n))).touch()
 value=i.inventory(many);assert value['status']=='FAILED namespace inventory'
 assert value['inventoryBefore']['overflow'] is True and value['inventoryBefore']['scannedAtLeast']==2049 and value['namesBefore']==[]
 checks.append({'case':'unrelated scan capped at2048plus sentinel without content reads','sample':value})
assert p.read_bytes()==before
result={'status':'PASS actual task namespace metadata inventory controls','helperBytes':len(before),'helperSHA256':hashlib.sha256(before).hexdigest(),'sourceBeforeAfterExact':True,'checks':checks,'temporarySyntheticFixturesRemoved':True,'scope':'Metadata of synthetic task-prefixed sibling paths only, unrelated file contents never read. No app/native/global descriptor acceptance.','checkedAt':time.time()};output.write_text(json.dumps(result,indent=2)+'\n');print(len(checks),'inventory controls passed')
