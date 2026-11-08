"""Isolated real-validator and real-publisher controls; never app acceptance."""
import base64,copy,hashlib,importlib.util,json,os,stat,tempfile,time
from pathlib import Path
from types import SimpleNamespace
B=Path(__file__).resolve().parent

def module(name,file):
 s=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
p=module('lc_controls_protocol','confirmation-lifecycle-protocol-r1.py')
e=module('lc_controls_evidence','confirmation-lifecycle-evidence-r1.py')
t=module('lc_controls_transport','confirmation-lifecycle-transport-r1.py')
g=module('lc_controls_regular','confirmation-window-evidence-r3.py')
sha=lambda x:hashlib.sha256(x).hexdigest()
rows=[]
def case(name,fn,accepted):
 error=None
 try:fn();actual=True
 except (AssertionError,ValueError,KeyError,TypeError,OSError) as ex:actual=False;error=type(ex).__name__+': '+str(ex)
 rows.append({'case':name,'expectedAccepted':accepted,'actualAccepted':actual,'error':error})
 assert actual is accepted,name
source=B/'health-legacy-confirmation-data-source248r1-host-audit.json'
old=json.loads(source.read_bytes());gate=json.loads(base64.b64decode(old['confirmationWindow']['gate']['base64']))
now=old['started'];gen='14175021-0D60-47F0-B096-E6CDF7317F2D'
main={'verificationProtocol':p.PROTOCOL,'binding':gate,'taskGeneration':gen,'checks':[],'problems':[],
 'events':[{'event':'created','at':now+1}, {'event':'wait-started','at':now+2,'taskCancelled':False,'closed':False,'consumed':False,'controlCancelled':False},
 {'event':'closed','at':now+3,'reason':'not-now','closed':True,'consumed':False,'controlCancelled':True},
 {'event':'wait-exit','at':now+4,'errorType':'CancellationError','taskCancelled':True,'closed':True,'consumed':False,'controlCancelled':True},
 {'event':'task-value-completed','at':now+5}]}
case('valid-external-task-completion',lambda:p.trace(main,gate,now,True),True)
for name,mutate in [
 ('defer-is-not-completion',lambda r:r['events'].pop()),
 ('completion-before-exit',lambda r:r['events'].__setitem__(slice(3,5),list(reversed(r['events'][3:5])))),
 ('wrong-close-reason',lambda r:r['events'][2].update(reason='presentation-change')),
 ('not-actually-cancelled',lambda r:r['events'][3].update(taskCancelled=False)),
 ('consumed-gate',lambda r:r['events'][2].update(consumed=True)),
 ('problem-present',lambda r:r['problems'].append('write failed')),
 ('wrong-generation',lambda r:r.update(taskGeneration='bad')),
 ('extra-task-reference',lambda r:r.update(task='retained'))]:
 r=copy.deepcopy(main);mutate(r);case(name,lambda r=r:p.trace(r,gate,now,True),False)
ack=json.dumps({**{k:gate[k] for k in ['runID','pid','sessionID','captureID','nonce']},'phase':'ui-observed'},sort_keys=True).encode()
# Known Data facts from actual248 bootstrap. Timing/request fields are synthetic
# isolated inputs; they are not observations of a Source250 run.
facts=copy.deepcopy(old['boundaries'][0]['observation']['bootstrapObservation']['fixed'])
check={'ordinal':1,'requestID':'823E9291-4065-411D-8695-93173A5AA05E','touchAt':now+7,'ackReadStartedAt':now+8,'ackReadFinishedAt':now+9,
 'acknowledgement':{'bytes':len(ack),'sha256':sha(ack),'base64':base64.b64encode(ack).decode()},'status':'checked','finishedAt':now+12,
 'nativeFacts':{'readStartedAt':now+10,'readFinishedAt':now+11,'fixed':facts,'healthConnected':False,'knownKeyWritten':False,'originalValuesVerified':True,
 'fixtureFlags':{'singleUseConsumed':False,'knownKeyWritten':False,'failed':False},'fixtureBinding':{k:gate[k] for k in ['runID','pid','sessionID','captureID']}}}
main['checks']=[{k:check[k] for k in ['ordinal','requestID','touchAt','status']}]
observation={'verificationProtocol':p.PROTOCOL,'binding':gate,'taskGeneration':gen,'check':check}
def validate(r):return p.check(r,main,ack,now+6,now+6.5,now+7.5,e)
case('valid-fresh-check',lambda:validate(observation),True)
for name,mutate in [
 ('cached-before-publication',lambda r:r['check'].update(touchAt=now+5)),
 ('duplicate-ordinal',lambda r:r['check'].update(ordinal=2)),
 ('bool-ordinal',lambda r:r['check'].update(ordinal=True)),
 ('missing-fresh-read',lambda r:r['check']['nativeFacts'].pop('readStartedAt')),
 ('preack-native-read',lambda r:r['check']['nativeFacts'].update(readStartedAt=now+6)),
 ('wrong-digest',lambda r:r['check']['acknowledgement'].update(sha256='0'*64)),
 ('wrong-closed-nonce',lambda r:r.update(binding=dict(gate,nonce=gen))),
 ('wrong-task-generation',lambda r:r.update(taskGeneration=check['requestID'])),
 ('health-connected',lambda r:r['check']['nativeFacts'].update(healthConnected=True)),
 ('write-occurred',lambda r:r['check']['nativeFacts'].update(knownKeyWritten=True)),
 ('consumed-fixture',lambda r:r['check']['nativeFacts']['fixtureFlags'].update(singleUseConsumed=True)),
 ('native-original-false',lambda r:r['check']['nativeFacts'].update(originalValuesVerified=False)),
 ('changed-fixed',lambda r:r['check']['nativeFacts']['fixed'][e.obs.KEYS[0]]['persisted'].update(payload=base64.b64encode(b'changed').decode()))]:
 r=copy.deepcopy(observation);mutate(r);case(name,lambda r=r:validate(r),False)
# Execute actual publisher against isolated files, including nofollow failures.
h=SimpleNamespace(read=g.regular,row=lambda x:{'bytes':len(x),'sha256':sha(x),'base64':base64.b64encode(x).decode()},identity=lambda path:{'mode':Path(path).lstat().st_mode})
with tempfile.TemporaryDirectory(prefix='lumen250-controls-') as folder:
 root=Path(folder);armed=dict(gate,taskGeneration=gen,phase='armed',targetPhase='host-ready')
 path=root/('Lumen-confirmation-lifecycle-relay-'+gate['runID'].lower()+'.json');window={}
 case('actual-publish-armed',lambda:t.publish(path,armed,window,lambda:None,h),True)
 late=dict(armed,phase='late-ack',targetPhase='host-late-ack',ackSHA256=sha(ack))
 case('actual-publish-late',lambda:t.publish(path,late,window,lambda:None,h),True)
 checked=dict(armed,phase='checked',targetPhase='host-checked',ackSHA256=sha(ack),checkRequestID=check['requestID'],checkOrdinal='1')
 case('actual-publish-checked',lambda:t.publish(path,checked,window,lambda:None,h),True)
 case('reject-fourth-relay',lambda:t.publish(path,checked,window,lambda:None,h),False)
 ackpath=root/('Lumen-confirmation-window-'+gate['runID'].lower()+'-'+gate['nonce'].lower()+'-ack.json')
 case('actual-publish-late-ack',lambda:t.publish_ack(ackpath,json.loads(ack),{},lambda:None,h),True)
 case('reject-existing-ack',lambda:t.publish_ack(ackpath,json.loads(ack),{},lambda:None,h),False)
 ackpath.unlink();ackpath.symlink_to(root/'missing')
 case('reject-dangling-symlink-ack',lambda:t.publish_ack(ackpath,json.loads(ack),{},lambda:None,h),False)
case('native-prepared-real248-prefix',lambda:e.check_state(old['boundaries'][0]['observation'],now,old['runID'],old['appPID']),True)
case('native-ready-real248-prefix',lambda:e.check_state(old['boundaries'][1]['observation'],now,old['runID'],old['appPID']),True)
case('reject-native-mutation',lambda:e.check_state(old['boundaries'][2]['observation'],now,old['runID'],old['appPID']),False)
result={'status':'PASS isolated actual validators and publisher controls','cases':rows,'sourceBindings':{f:{'bytes':(B/f).stat().st_size,'sha256':sha((B/f).read_bytes())} for f in ['confirmation-lifecycle-evidence-r1.py','confirmation-lifecycle-protocol-r1.py','confirmation-lifecycle-transport-r1.py']},'priorRealInput':{'file':source.name,'sha256':sha(source.read_bytes())},'scope':'Synthetic lifecycle timing/request/trace fixtures and real248 Data bootstrap/ready rows, real isolated publisher files; no current250 app/runtime/native/worker completion acceptance. Temporary files removed by TemporaryDirectory.','checkedAt':time.time()}
out=B/'source250-lifecycle-controls-r1.json';assert not out.exists();out.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'status':result['status'],'cases':len(rows),'output':out.name}))
