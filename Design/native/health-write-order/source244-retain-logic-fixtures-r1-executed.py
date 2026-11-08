"""Archive only known synthetic roots from this batch, without following links."""
from pathlib import Path
import os,stat,json,base64,gzip,hashlib,time,tempfile
B=Path(__file__).resolve().parent;sha=lambda x:hashlib.sha256(x).hexdigest();names=['source244-origin-review-r1.json','source244-logic-legacy-origin-r1.json','source244-logic-legacy-transaction-r1.json','source244-logic-legacy-boundaries-r1.json'];roots={};total=0;files=0
for name in names:
 report=json.loads((B/name).read_bytes());root=Path(report['retainedRoot']);assert root.parent==Path(tempfile.gettempdir()) and root.name.startswith(('Lumen-origin-review-','Lumen-legacy-origin-','Lumen-legacy-transaction-','Lumen-legacy-boundaries-'));assert not root.is_symlink() and stat.S_ISDIR(root.lstat().st_mode)
 rows=[];paths=[root]
 for parent,dirs,leaves in os.walk(root,followlinks=False):paths.extend(Path(parent)/n for n in sorted(dirs+leaves))
 for p in paths:
  s=p.lstat();row={'path':str(p.relative_to(root)),'identity':{k:getattr(s,k) for k in ['st_ino','st_dev','st_mode','st_nlink','st_size','st_mtime_ns']}}
  if stat.S_ISREG(s.st_mode):
   assert s.st_size<=4*1024*1024;data=p.read_bytes();total+=len(data);files+=1;assert total<=64*1024*1024;row.update(kind='regular',bytes=len(data),sha256=sha(data),base64=base64.b64encode(data).decode())
  elif stat.S_ISDIR(s.st_mode):row['kind']='directory'
  elif stat.S_ISLNK(s.st_mode):row.update(kind='symlink',target=os.readlink(p))
  elif stat.S_ISFIFO(s.st_mode):row['kind']='fifo'
  else:raise AssertionError(str(p))
  rows.append(row)
 roots[str(root)]={'report':name,'entries':rows}
raw=json.dumps({'roots':roots},sort_keys=True).encode();fixture='source244-logic-synthetic-roots-r1.json.gz';assert not (B/fixture).exists();(B/fixture).write_bytes(gzip.compress(raw,mtime=0));out={'status':'PASS fullknownsyntheticroots retainedwithoutfollowinglinks','roots':len(roots),'regularFiles':files,'regularBytes':total,'fixture':fixture,'decodedBytes':len(raw),'decodedSHA256':sha(raw),'scope':'Only actual244logicgeneratedroots; symlinktargets/FIFOs recordedwithoutopening; no deletions or nativeproof','checkedAt':time.time()};p=B/'source244-logic-synthetic-roots-r1.json';assert not p.exists();p.write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out))
