"""Actual metadata relay publisher on isolated files; no simulator/process query."""
from pathlib import Path
import base64,gzip,hashlib,importlib.util,json,tempfile,time,types
B=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('relay_publish_controls',B/'confirmation-runner-relay-r1.py');relay=importlib.util.module_from_spec(spec);spec.loader.exec_module(relay)
sha=lambda b:hashlib.sha256(b).hexdigest()
row=lambda b:{'bytes':len(b),'sha256':sha(b),'base64':base64.b64encode(b).decode()}
def read(p,limit=4096):
 p=Path(p);assert not p.is_symlink() and p.is_file() and p.stat().st_size<=limit;return p.read_bytes()
h=types.SimpleNamespace(read=read,row=row,identity=lambda p:{k:getattr(p.lstat(),k) for k in ['st_ino','st_dev','st_mode','st_nlink','st_size','st_mtime_ns']})
u='C7ED94D3-DDC6-45DD-ACC9-EC583731AEC7';v='ED54372B-AF7D-4972-A183-EDA40AD6C4EB';gate={'runID':u,'pid':'123','sessionID':v,'captureID':u,'nonce':v,'appearanceID':u,'domains':'meals','legacyDomains':'meals','omitPhotos':'false'}
results=[];fixtures=[]
def exercise(name,action,wanted):
 with tempfile.TemporaryDirectory(prefix='lumen248-relay-publish-') as folder:
  root=Path(folder);path=root/('Lumen-confirmation-relay-'+u.lower()+'.json');window={};saved=root/'canonical.json'
  def persist():saved.write_text(json.dumps(window,sort_keys=True))
  persist()
  try:action(path,window,persist);accepted=True;error=None
  except (AssertionError,OSError,ValueError) as e:accepted=False;error=type(e).__name__+': '+str(e)
  assert accepted==wanted,name
  results.append({'name':name,'accepted':accepted,'expected':wanted});fixtures.append({'name':name,'canonical':json.loads(saved.read_bytes()),'final':row(path.read_bytes()) if path.is_file() and not path.is_symlink() else None,'error':error})
def armed(p,w,save):return relay.publish(p,relay.message(gate,'armed'),w,save,h)
def mutated(p,w,save):return relay.publish(p,relay.message(gate,'mutated','a'*64),w,save,h)
def both(p,w,save):armed(p,w,save);mutated(p,w,save);assert len(w['relays'])==2 and all(r['status']=='PUBLISHED metadata-only relay' for r in w['relays'])
exercise('exact two atomic metadata generations',both,True)
exercise('reject unknown phase',lambda p,w,s:relay.message(gate,'unknown'),False)
exercise('reject missing native digest',lambda p,w,s:relay.message(gate,'mutated'),False)
exercise('reject invalid native digest',lambda p,w,s:relay.message(gate,'mutated','Z'*64),False)
exercise('reject progress before initial relay',mutated,False)
exercise('reject duplicate armed publication',lambda p,w,s:(armed(p,w,s),armed(p,w,s)),False)
exercise('reject third generation',lambda p,w,s:(both(p,w,s),mutated(p,w,s)),False)
def changedgate(p,w,save):
 armed(p,w,save);changed=dict(gate,nonce=u);relay.publish(p,relay.message(changed,'mutated','a'*64),w,save,h)
exercise('reject gate change across generations',changedgate,False)
def preexisting(p,w,save):p.write_bytes(b'other');armed(p,w,save)
exercise('reject unexpected preexisting relay',preexisting,False)
def tamper(p,w,save):armed(p,w,save);p.write_bytes(b'tampered');mutated(p,w,save)
exercise('reject altered previous relay',tamper,False)
def symlink(p,w,save):
 target=p.parent/'target';target.write_bytes(b'other');p.symlink_to(target);armed(p,w,save)
exercise('reject preexisting relay symlink',symlink,False)
def collision(p,w,save):
 p.with_suffix('.armed.tmp').write_bytes(b'other');armed(p,w,save)
exercise('retain failed exclusive temporary publication',collision,False)
archive=json.dumps({'publisherSource':(B/'confirmation-runner-relay-r1.py').read_text(),'fixtures':fixtures}).encode();(B/'source248-relay-publish-controls-r1-fixtures.json.gz').write_bytes(gzip.compress(archive,mtime=0));out={'status':'PASS actual metadata publisher/exclusive atomic generations on isolated real files','count':len(results),'cases':results,'decodedBytes':len(archive),'decodedSHA256':sha(archive),'scope':'Actual publisher and filesystem, synthetic metadata/identity; no real runner path/native/visibility/ACK/cancellation or powerfailure guarantee','checkedAt':time.time()};(B/'source248-relay-publish-controls-r1.json').write_text(json.dumps(out,indent=2)+'\n');print(len(results),'actual relay publication controls PASS')
