"""Actual lifecycle function/observe caller with retained native fixtures and isolated paths."""
from pathlib import Path
from types import SimpleNamespace
import ast,base64,copy,hashlib,importlib.util,json,os,subprocess,tempfile,time
B=Path(__file__).resolve().parent

def module(name,file):
 spec=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
E=module('caller_evidence','confirmation-expiry-evidence-r1.py');H=E.h;V=module('caller_protocol','confirmation-expiry-protocol-r1.py');G=module('caller_geometry','confirmation-window-evidence-r3.py')
original=json.loads((B/'health-confirmation-notnow-data-source255r1-driver-observations.json').read_bytes());oldwindow=original['confirmationWindow'];rawvalue=lambda key:base64.b64decode(oldwindow[key]['versions'][-1]['base64'],validate=True)
queries=[]
def deny(*args,**kwargs):queries.append(str(args));raise AssertionError('Real process query denied in isolated caller')
for key in ['Popen','run','check_output','check_call','call']:setattr(subprocess,key,deny)
rows=[]
for label,expected in [('before-waiter','pending'),('active-waiter','pending'),('deadline-closed-before-exit','pending'),('deadline-publication','expired'),('expired-ui-missing-repeat','expiry-repeat'),('elapsed-too-short','rejected'),('deadline-already-completed-before-publication','rejected')]:
 file='confirmation-expiry-driver-r1.py'
 with tempfile.TemporaryDirectory(prefix='lumen257-host-caller-') as temp:
  group=Path(temp)/'group';group.mkdir();runner=Path(temp)/'runner';(runner/'tmp').mkdir(parents=True)
  state=copy.deepcopy(original);window=state['confirmationWindow'];window['runner']=str(runner);window.pop('hostCheckCompleted',None)
  gate=json.loads(rawvalue('gate'));run=gate['runID'].lower();nonce=gate['nonce'].lower();stem='Lumen-confirmation-window-'+run+'-'+nonce
  gatepath=group/(stem+'.json');gatepath.write_bytes(rawvalue('gate'));ackpath=group/(stem+'-ack.json');ack=base64.b64decode(window['ackBytes']['base64'],validate=True);ackpath.write_bytes(ack)
  tracepath=group/('Lumen-confirmation-lifecycle-'+run+'-'+nonce+'.json');checkpath=tracepath.with_suffix('.check-1.json');trace=json.loads(rawvalue('trace'));trace['checks'][0]['file']=str(checkpath);check=json.loads(rawvalue('check'))
  if label=='native-check-rejected':check['check']['status']='synthetic-rejected'
  checkraw=json.dumps(check,sort_keys=True).encode();checkpath.write_bytes(checkraw);trace['checks'][0]['bytes']=len(checkraw);trace['checks'][0]['sha256']=hashlib.sha256(checkraw).hexdigest();trace['verificationProtocol']=V.PROTOCOL
  trace['events'][2]['reason']='deadline'
  trace['events'][3].update(errorType='Lumen.HealthLegacyTargetChangeUIFixture.Failure',taskCancelled=False,expiryClock='ContinuousClock',expiryLimitSeconds=90,expiryElapsedSeconds=90,expiryElapsedAttoseconds=0)
  check['verificationProtocol']=V.PROTOCOL;checkraw=json.dumps(check,sort_keys=True).encode();checkpath.write_bytes(checkraw)
  trace['checks'][0].update(bytes=len(checkraw),sha256=hashlib.sha256(checkraw).hexdigest())
  expired_trace=copy.deepcopy(trace);expired_trace['events']=expired_trace['events'][:4];expired_trace['checks']=[]
  expired_raw=json.dumps(expired_trace).encode();window['expiryTrace']={'readAt':trace['events'][3]['at'],**H.row(expired_raw)}
  expired_relay=dict(window['relays'][0]['value'],phase='expired',targetPhase='host-expired',expiredTraceSHA256=H.sha(expired_raw))
  window['relays'].insert(1,{'value':expired_relay});window['hostExpiryCheckpointPublished']=True
  if label=='truthy-expiry-flag':window['hostExpiryCheckpointPublished']='yes'
  if label=='wrong-expired-digest':expired_relay['expiredTraceSHA256']='b'*64
  tracepath.write_text(json.dumps(trace))
  for phase in ['presented','expired','dismissed','checked']:
   if label=='checked-marker-missing' and phase=='checked':continue
   marker=json.loads(rawvalue('presented' if phase=='expired' else phase));marker['scope']='actual-confirmation-expiry-before-notnow-late-ack'
   marker['attachmentName']=marker['attachmentName'].replace('health-confirmation-notnow-','health-confirmation-expiry-')
   if phase=='expired':
    marker.update(phase='expired',attachmentName='health-confirmation-expiry-expired',expiredRelay=copy.deepcopy(expired_relay),recoverEnabled=True,cancelEnabled=True,recoverHittable=True,cancelHittable=True,expiryWaitStartedAt=marker['at'],expiryRelayObservedAt=trace['events'][3]['at'],at=trace['events'][3]['at'])
   if phase=='dismissed':
    marker['touchAt']=trace['events'][3]['at'];marker['tapReturnedAt']=max(marker['tapReturnedAt'],marker['touchAt']);marker['at']=max(marker['at'],marker['tapReturnedAt'])
   (runner/'tmp'/('Lumen-confirmation-expiry-ui-'+nonce+'-'+phase+'.json')).write_text(json.dumps(marker))
  if label=='wrong-ack':ackpath.write_bytes(b'{}')
  if label=='truthy-nonboolean-not-complete':window['hostCheckCompleted']={'synthetic':True}
  # Start from exact armed-only state, with no gate ack and no later UI.
  ackpath.unlink();window['relays']=window['relays'][:1];window.pop('hostExpiryCheckpointPublished',None)
  for phase in ['expired','dismissed','checked']:
   path=runner/'tmp'/('Lumen-confirmation-expiry-ui-'+nonce+'-'+phase+'.json')
   if path.exists():path.unlink()
  trace['checks']=[]
  count={'before-waiter':1,'active-waiter':2,'deadline-closed-before-exit':3,'deadline-already-completed-before-publication':5}.get(label,4)
  trace['events']=trace['events'][:count]
  if label=='elapsed-too-short':trace['events'][3]['expiryElapsedSeconds']=89
  tracepath.write_text(json.dumps(trace))
  calls=[]
  def persist():pass
  def preserved(*args):calls.append('protected-after-check')
  def origin(*args):calls.append('origin-after-check');return copy.deepcopy(original['boundaries'][1]['originEvents'])
  def publish(path,value,window,persist,h):calls.append('checked-relay');window['relays'].append({'value':value})
  tree=ast.parse((B/file).read_bytes());nodes=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ['observe','confirmation_gate']];assert len(nodes)==2
  env={'Path':Path,'os':os,'time':time,'json':json,'base64':base64,'subprocess':subprocess,'state':state,'h':H,'v':V,'gate':G,'e':SimpleNamespace(origin_trace=origin,obs=E.obs,h=H),'relay':SimpleNamespace(publish=publish),'preserved':preserved,'persist':persist}
  exec(compile(ast.fix_missing_locations(ast.Module(body=nodes,type_ignores=[])),'actual-whole-host-and-observer','exec'),env)
  failure=None
  try:env['confirmation_gate'](group)
  except (AssertionError,FileNotFoundError) as error:failure=type(error).__name__+': '+str(error)
  print(label,expected,failure,calls,flush=True)
  if expected in ['expired','expiry-repeat']:
   assert failure is None and calls==['protected-after-check','origin-after-check','checked-relay']
   assert window['hostExpiryCheckpointPublished'] is True
   assert len(window['relays'])==2 and window['relays'][1]['value']['phase']=='expired'
   assert window['relays'][1]['value']['expiredTraceSHA256']==window['expiryTrace']['sha256']
   assert len(json.loads(base64.b64decode(window['expiryTrace']['base64']))['events'])==4
   assert not ackpath.exists() and isinstance(window.get('presented'),dict)
   if expected=='expiry-repeat':
    calls.clear();env['confirmation_gate'](group);assert calls==[] and window['hostExpiryCheckpointPublished'] is True
  elif expected=='rejected':assert failure is not None and calls==[] and window.get('hostExpiryCheckpointPublished') is not True
  else:assert failure is None and calls==[] and window.get('hostExpiryCheckpointPublished') is not True
  rows.append({'case':label,'actualSource':file,'expected':expected,'failure':failure,'actualObserveExecuted':True,'completionFlag':window.get('hostCheckCompleted'),'checkedMarkerStillDictionary':isinstance(window.get('checked'),dict),'postCheckStages':calls,'status':'PASS'})
assert not queries
sources={}
for n in ['confirmation-expiry-driver-r1.py','confirmation-expiry-protocol-r1.py','confirmation-window-evidence-r3.py']:
 raw=(B/n).read_bytes();sources[n]={'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
r={'status':'PASS actual whole expiry confirmation_gate+observe pending and deadline-publication paths using synthetic clock metadata','count':len(rows),'cases':rows,'sources':sources,'realProcessQueries':queries,'scope':'Synthetic expiry facts/expired relay are expressly fixture-only, not native clock or UI proof. Real actual observed-marker storage and protocol validators execute in unique TemporaryDirectory files, with native255 JSON only as retained fixture input. Trace header file/hash adapted to fixture copy; no native/fresh process proof. Only protection/origin/publisher persistence dependencies injected and explicitly recorded. New completes once, retains checked dictionary, repeated call skips duplicate stages; wrong ack/rejected nativeCheck/pending marker never publish. All fixture files automatically removed.','checkedAt':time.time()};p=B/'source257-host-deadline-caller-controls-r1.json';assert not p.exists();p.write_text(json.dumps(r,indent=2)+'\n');print(r['status'])
