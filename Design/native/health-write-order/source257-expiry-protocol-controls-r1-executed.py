"""Pure expiry validators and real atomic relay publication, using synthetic fixtures."""
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4
import base64,copy,hashlib,importlib.util,json,tempfile,time
B=Path(__file__).resolve().parent

def module(name,file):
 s=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
v=module('expiry_protocol_controls','confirmation-expiry-protocol-r1.py');t=module('expiry_transport_controls','confirmation-expiry-transport-r1.py')
binding={k:str(uuid4()).upper() for k in ['runID','sessionID','captureID','nonce','appearanceID']};binding.update(pid='123',domains='meals',legacyDomains='meals',omitPhotos='false')
fields=[{},dict(taskCancelled=False,closed=False,consumed=False,controlCancelled=False),dict(reason='deadline',closed=True,consumed=False,controlCancelled=True),dict(errorType='Lumen.HealthLegacyTargetChangeUIFixture.Failure',taskCancelled=False,closed=True,consumed=False,controlCancelled=True,expiryClock='ContinuousClock',expiryLimitSeconds=90,expiryElapsedSeconds=90,expiryElapsedAttoseconds=0),{}]
trace=dict(verificationProtocol=v.PROTOCOL,binding=binding,taskGeneration=str(uuid4()).upper(),events=[dict(event=n,at=100+i,**f) for i,(n,f) in enumerate(zip(['created','wait-started','closed','wait-exit','task-value-completed'],fields))],checks=[],problems=[])
rows=[]
def expect(name,wanted,action):
 error=None
 try:action()
 except (AssertionError,KeyError,ValueError,TypeError) as e:error=type(e).__name__+': '+str(e)
 assert (error is None)==wanted,name
 rows.append(dict(case=name,accepted=error is None,expected=wanted,error=error))
for n in range(1,6):
 x=copy.deepcopy(trace);x['events']=x['events'][:n];expect('prefix-'+str(n),True,lambda:v.trace(x,binding,99))
for key,val in [('expiryClock','Date'),('expiryLimitSeconds',89),('expiryElapsedSeconds',89),('expiryElapsedSeconds',True),('expiryElapsedSeconds',90.0),('expiryElapsedAttoseconds',-1),('expiryElapsedAttoseconds',10**18),('taskCancelled',True),('closed',False),('consumed',True),('controlCancelled',False),('errorType','CancellationError')]:
 x=copy.deepcopy(trace);x['events'][3][key]=val;expect('reject-'+key+'-'+str(val),False,lambda:v.trace(x,binding,99,complete=True))
for i,key,val in [(2,'reason','not-now'),(1,'taskCancelled',True),(2,'consumed',True)]:
 x=copy.deepcopy(trace);x['events'][i][key]=val;expect('reject-event-'+str(i)+'-'+key,False,lambda:v.trace(x,binding,99))
x=copy.deepcopy(trace);x['events']=x['events'][:4];expect('incomplete-not-complete',False,lambda:v.trace(x,binding,99,complete=True))
sha=lambda data:hashlib.sha256(data).hexdigest()
h=SimpleNamespace(read=lambda p,limit:Path(p).read_bytes(),row=lambda data:dict(bytes=len(data),sha256=sha(data),base64=base64.b64encode(data).decode()),identity=lambda p:dict(inode=Path(p).stat().st_ino))
armed=dict(binding,taskGeneration=trace['taskGeneration'],phase='armed',targetPhase='host-ready');expired=dict(armed,phase='expired',targetPhase='host-expired',expiredTraceSHA256='a'*64);late=dict(armed,phase='late-ack',targetPhase='host-late-ack',ackSHA256='b'*64);checked=dict(armed,phase='checked',targetPhase='host-checked',ackSHA256='b'*64,checkRequestID=str(uuid4()).upper(),checkOrdinal='1')
with tempfile.TemporaryDirectory(prefix='lumen257-expiry-protocol-') as temp:
 p=Path(temp)/('Lumen-confirmation-expiry-relay-'+binding['runID'].lower()+'.json');window={}
 for row in [armed,expired,late,checked]:
  expect('publish-'+row['phase'],True,lambda:t.publish(p,row,window,lambda:None,h));assert json.loads(p.read_bytes())==row
 expect('no-fifth-relay',False,lambda:t.publish(p,checked,window,lambda:None,h))
 for name,row in [('skip-expiry',late),('expired-wrong-hash',dict(expired,expiredTraceSHA256='x')),('expired-extra-ack',dict(expired,ackSHA256='b'*64))]:
  q=Path(temp)/name;q.mkdir();path=q/p.name;w={};t.publish(path,armed,w,lambda:None,h)
  expect(name,False,lambda:t.publish(path,row,w,lambda:None,h));assert json.loads(path.read_bytes())==armed
sources={}
for file in ['confirmation-expiry-protocol-r1.py','confirmation-expiry-transport-r1.py']:
 raw=(B/file).read_bytes();sources[file]=dict(bytes=len(raw),sha256=sha(raw))
result=dict(status='PASS isolated actual expiry schema and atomic relay controls',count=len(rows),cases=rows,sources=sources,scope='Synthetic metadata only, actual validators and temporary file atomic transport. No real elapsed clock, app/native UI, source/build acceptance or postrun checker claimed.',checkedAt=time.time())
p=B/'source257-expiry-protocol-controls-r1.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n');print(result['status'],result['count'])
