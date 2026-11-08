"""Retain actual failed case mandatory checker and complete attachment export."""
from pathlib import Path
import base64,gzip,hashlib,json,shutil,subprocess,time
B=Path(__file__).resolve().parent;P='health-confirmation-notnow-data-source252r1';stem='HealthConfirmationNotNowDataSource252R1';raw=Path('/tmp/LumenBatch44Checks');sha=lambda x:hashlib.sha256(x).hexdigest()
def row(data):return {'bytes':len(data),'sha256':sha(data),'base64':base64.b64encode(data).decode()}
assert shutil.disk_usage(B).free>8*1024**3
command=['python3',str(B/'check-confirmation-lifecycle-r2.py'),P,'--checker-source','durable-source-r252.json','--case-source','durable-source-r252.json','--build','health-target-change-source252-r1-build.json','--trial','Source252R1']
proc=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE);stdout,stderr=proc.communicate();checker={'command':command,'pid':proc.pid,'exit':proc.returncode,'stdout':row(stdout),'stderr':row(stderr),'checkedAt':time.time()}
p=B/'source252-mandatory-r2-checker-r1.json';assert not p.exists();p.write_text(json.dumps(checker,indent=2)+'\n');assert proc.returncode==1
root=raw/(stem+'All');assert not root.exists();command=['xcrun','xcresulttool','export','attachments','--path',str(raw/(stem+'.xcresult')),'--output-path',str(root)]
r=subprocess.run(command,capture_output=True);query={'command':command,'exit':r.returncode,'stdout':row(r.stdout),'stderr':row(r.stderr),'checkedAt':time.time()};p=B/(P+'-all-original-export-query.json');assert not p.exists();p.write_text(json.dumps(query,indent=2)+'\n');assert r.returncode==0
manifest=(root/'manifest.json').read_bytes();(B/(P+'-all-original-manifest.json.gz')).write_bytes(gzip.compress(manifest,mtime=0));rows=[];other={};kinds={}
for path in sorted(root.rglob('*')):
 assert not path.is_symlink()
 if not path.is_file() or path==root/'manifest.json':continue
 data=path.read_bytes();name=str(path.relative_to(root));suffix=path.suffix.lower();kind={'.png':'png','.json':'json','.mp4':'video'}.get(suffix,'binary-plist' if data.startswith(b'bplist') else 'text' if suffix in ['.txt','.log','.xml'] else 'other')
 fact={'file':name,'kind':kind,'bytes':len(data),'sha256':sha(data)}
 if kind in ['png','json','video']:
  target=B/(P+'-'+path.name);assert not target.exists() or target.read_bytes()==data;target.write_bytes(data);fact['retained']=target.name
 else:other[name]=row(data)
 rows.append(fact);kinds[kind]=kinds.get(kind,0)+1
archive=json.dumps({'files':other}).encode();othername=P+'-all-other-originals.json.gz';(B/othername).write_bytes(gzip.compress(archive,mtime=0))
index={'status':'Full actual failedcase original export retained; no native acceptance','count':len(rows),'kinds':kinds,'rows':rows,'completeManifest':{'file':P+'-all-original-manifest.json.gz','bytes':len(manifest),'sha256':sha(manifest)},'otherArchive':{'file':othername,'decodedBytes':len(archive),'decodedSHA256':sha(archive)},'scope':'All original bytes preserved; screenshot-view flags untouched, video byte-retained unplayed if any. No cleanup/reset/source edits.','checkedAt':time.time()};p=B/(P+'-all-originals.json');assert not p.exists();p.write_text(json.dumps(index,indent=2)+'\n');print(json.dumps({'checkerPID':checker['pid'],'checkerExit':checker['exit'],'fullExportExit':r.returncode,'count':len(rows),'kinds':kinds,'largest':max(rows,key=lambda x:x['bytes'])}))
