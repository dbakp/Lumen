"""Exercise actual pure marker predicate and nofollow reader; no simulator queries."""
import copy,hashlib,importlib.util,json,os,tempfile,time
from pathlib import Path
B=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('gate_controls',B/'confirmation-window-evidence-r3.py');g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
u='C7ED94D3-DDC6-45DD-ACC9-EC583731AEC7';v='ED54372B-AF7D-4972-A183-EDA40AD6C4EB'
gate={'runID':u,'pid':'123','sessionID':v,'captureID':u,'nonce':v,'appearanceID':u,'domains':'meals','legacyDomains':'meals','omitPhotos':'false'}
native={k:gate[k] for k in ['runID','sessionID','captureID']};native.update(pid=123,status='ready',sequence=3,knownKeyWritten=False,singleUseConsumed=False)
r=lambda x,y,w,h:dict(x=x,y=y,width=w,height=h)
marker={'gate':dict(gate,phase='armed',targetPhase='host-ready'),'scope':'actual-legacy-target-change-during-confirmation-runner-relay','title':'Replace selected data?','body':g.BODY,'appFrame':r(0,0,402,874),'alertFrame':r(40,345,322,210),'bodyFrame':r(70,390,260,80),'recoverFrame':r(210,490,130,48),'cancelFrame':r(60,490,130,48),'at':100.0,'attachmentName':'health-legacy-target-change-confirmation-before-mutation','imageBytes':200000,'imageSHA256':'a'*64}
rows=[]
def check(name,change=None,accept=False):
 a,b,c=copy.deepcopy(gate),copy.deepcopy(native),copy.deepcopy(marker)
 if change:change(a,b,c)
 try:g.validate(a,b,c,99,101);actual=True
 except (AssertionError,ValueError,TypeError,KeyError):actual=False
 assert actual==accept,name
 rows.append({'name':name,'accepted':actual,'expected':accept})
check('exact matched native-ready real UI marker',accept=True)
for key in ['nonce','runID','sessionID','captureID','appearanceID']:
 check('wrong UI '+key,lambda a,b,c,k=key:c['gate'].__setitem__(k,'D7ED94D3-DDC6-45DD-ACC9-EC583731AEC7'))
for key,value in [('pid','0123'),('domains','workouts'),('legacyDomains',''),('omitPhotos','true')]:
 check('wrong gate '+key,lambda a,b,c,k=key,v=value:a.__setitem__(k,v))
for key,value in [('status','mutated'),('sequence',7),('knownKeyWritten',True),('singleUseConsumed',True),('pid',124)]:
 check('wrong native '+key,lambda a,b,c,k=key,v=value:b.__setitem__(k,v))
for key,value in [('at',98),('at',102),('at',float('nan')),('title','Other alert'),('body','Short consequence'),('imageBytes',True),('imageSHA256','z'*64),('attachmentName','other')]:
 check('wrong marker '+key+' '+str(value),lambda a,b,c,k=key,v=value:c.__setitem__(k,v))
check('armed state must match',lambda a,b,c:c['gate'].__setitem__('phase','mutated'))
check('actual ready acknowledgement required',lambda a,b,c:c['gate'].__setitem__('targetPhase','ready'))
for key in ['bodyFrame','recoverFrame','cancelFrame']:
 check('out of alert '+key,lambda a,b,c,k=key:c[k].__setitem__('y',850))
 check('nonfinite '+key,lambda a,b,c,k=key:c[k].__setitem__('width',float('inf')))
check('duplicate action frame',lambda a,b,c:c.__setitem__('cancelFrame',c['recoverFrame']))
check('small action',lambda a,b,c:c['recoverFrame'].__setitem__('height',43))
with tempfile.TemporaryDirectory(prefix='lumen246-gate-controls-') as folder:
 root=Path(folder);p=root/'marker.json';data=json.dumps(marker).encode();p.write_bytes(data);assert g.regular(p)==data;rows.append({'name':'real bounded regular marker read','accepted':True,'expected':True})
 for name,make in [('symlink',lambda:(root/'link').symlink_to(p)),('fifo',lambda:os.mkfifo(root/'link')),('directory',lambda:(root/'link').mkdir()),('oversized',lambda:(root/'link').write_bytes(b'x'*16385))]:
  link=root/'link';make()
  try:g.regular(link);ok=True
  except (AssertionError,OSError):ok=False
  assert not ok,name
  rows.append({'name':'reject real '+name,'accepted':False,'expected':False})
  if link.is_dir():link.rmdir()
  else:link.unlink()
 p.unlink();p.write_bytes(b'')
 try:g.regular(p);raise RuntimeError('empty accepted')
 except AssertionError:rows.append({'name':'reject empty marker','accepted':False,'expected':False})
output={'status':'PASS actual pure marker predicate and nofollow file controls','checks':rows,'count':len(rows),'processQueries':0,'scope':'No actual alert, runner visibility, asynchronous cancellation, SwiftUI typing, app/native or runtime acceptance','checkedAt':time.time()}
(B/'source248-confirmation-marker-controls-r1.json').write_text(json.dumps(output,indent=2)+'\n');print(len(rows),'controls PASS')
