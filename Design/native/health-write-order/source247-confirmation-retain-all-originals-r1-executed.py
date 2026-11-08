"""Readonly full export plus byte-exact retention of every original attachment."""
from pathlib import Path
import json,gzip,base64,hashlib,shutil,stat,time,subprocess,collections
b=Path('Design/native/health-write-order');stem='HealthLegacyConfirmationDataSource247R1';prefix='health-legacy-confirmation-data-source247r1';raw=Path('/tmp/LumenBatch44Checks')/(stem+'All');out=b/'source247-native-all-original-export-r1.json';assert not raw.exists() and not out.exists();assert shutil.disk_usage('.').free>8*1024**3
sha=lambda d:hashlib.sha256(d).hexdigest();command=['xcrun','xcresulttool','export','attachments','--path',str(raw.parent/(stem+'.xcresult')),'--output-path',str(raw)];r=subprocess.run(command,capture_output=True)
receipt={'command':command,'exit':r.returncode,'scope':'Readonly complete actual attachment acquisition; native outcome unchanged','checkedAt':time.time()}
for stream,data in [('stdout',r.stdout),('stderr',r.stderr)]:
 n=prefix+'-all-export-'+stream+'.gz';assert not (b/n).exists();(b/n).write_bytes(gzip.compress(data,mtime=0));receipt[stream]={'file':n,'bytes':len(data),'sha256':sha(data)}
out.write_text(json.dumps(receipt,indent=2)+'\n');assert r.returncode==0
manifest=(raw/'manifest.json').read_bytes();cases=json.loads(manifest);rows=[];payloads={};kinds=collections.Counter();seen=set()
for case in cases:
 for metadata in case['attachments']:
  name=metadata['exportedFileName'];assert Path(name).name==name and name not in seen;seen.add(name);p=raw/name;assert stat.S_ISREG(p.lstat().st_mode) and not p.is_symlink();data=p.read_bytes();kind='png' if data.startswith(b'\x89PNG\r\n\x1a\n') else 'video' if name.endswith('.mp4') else 'json' if name.endswith('.json') else 'binary-plist' if data.startswith(b'bplist00') else 'text' if name.endswith('.txt') else 'other';kinds[kind]+=1
  row={'file':name,'metadata':metadata,'test':case['testIdentifier'],'bytes':len(data),'sha256':sha(data),'kind':kind,'humanOpened':False}
  if kind in ['png','json','video']:
   dest=b/(prefix+'-'+name)
   if dest.exists():assert not dest.is_symlink() and dest.read_bytes()==data
   else:shutil.copyfile(p,dest);assert dest.read_bytes()==data
   row['retained']=dest.name
   if kind=='video':row['inspection']='Full bytes/hash retained unplayed, no motion/speech credit'
  else:payloads[name]={'bytes':len(data),'sha256':sha(data),'base64':base64.b64encode(data).decode()};row['retained']='full other-payload archive'
  rows.append(row)
assert {p.name for p in raw.iterdir()}==seen|{'manifest.json'}
encoded=json.dumps({'files':payloads,'scope':'Every additional original retained byte-exact, not automatically interpreted as an independent UI frame'},sort_keys=True).encode();name=prefix+'-all-other-payloads.json.gz';assert not (b/name).exists();(b/name).write_bytes(gzip.compress(encoded,mtime=0));mname=prefix+'-all-original-manifest.json.gz';assert not (b/mname).exists();(b/mname).write_bytes(gzip.compress(manifest,mtime=0))
actual=json.loads((b/(prefix+'-outcome.json')).read_text());index={'status':'Complete actual original attachments retained; native outcome preserved','count':len(rows),'kinds':dict(kinds),'rows':rows,'otherArchive':{'file':name,'bytes':(b/name).stat().st_size,'sha256':sha((b/name).read_bytes()),'decodedBytes':len(encoded),'decodedSHA256':sha(encoded)},'completeManifest':{'file':mname,'bytes':len(manifest),'sha256':sha(manifest)},'nativeExit':actual.get('nativeExit'),'driverExit':actual.get('driverExit'),'scope':'Acquisition index immutable; human opens separately recorded. Any video retained unplayed; no motion/speech credit. Raw exports retained until full root/critic/exact backup.','checkedAt':time.time()};(b/(prefix+'-all-originals.json')).write_text(json.dumps(index,indent=2)+'\n');print(json.dumps({'count':len(rows),'kinds':dict(kinds),'otherPayloads':len(payloads),'nativeExit':index['nativeExit'],'driverExit':index['driverExit']}))
