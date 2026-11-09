"""Actual lifecycle function/observe caller with retained native fixtures and isolated paths."""
from pathlib import Path
from types import SimpleNamespace
import ast,base64,copy,hashlib,importlib.util,json,os,subprocess,tempfile,time
B=Path(__file__).resolve().parent

def module(name,file):
 spec=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
E=module('caller_evidence','confirmation-lifecycle-evidence-r1.py');H=E.h;V=module('caller_protocol','confirmation-lifecycle-protocol-r1.py');G=module('caller_geometry','confirmation-window-evidence-r3.py')
original=json.loads((B/'health-confirmation-notnow-data-source255r1-driver-observations.json').read_bytes());oldwindow=original['confirmationWindow'];rawvalue=lambda key:base64.b64decode(oldwindow[key]['versions'][-1]['base64'],validate=True)
queries=[]
def deny(*args,**kwargs):queries.append(str(args));raise AssertionError('Real process query denied in isolated caller')
for key in ['Popen','run','check_output','check_call','call']:setattr(subprocess,key,deny)
rows=[]
for label,file,expected in [('old-marker-collision','confirmation-lifecycle-driver-r2.py','old-return'),('new-completion','confirmation-lifecycle-driver-r3.py','completed'),('new-repeat','confirmation-lifecycle-driver-r3.py','repeat'),('checked-marker-missing','confirmation-lifecycle-driver-r3.py','pending'),('wrong-ack','confirmation-lifecycle-driver-r3.py','rejected'),('native-check-rejected','confirmation-lifecycle-driver-r3.py','rejected'),('truthy-nonboolean-not-complete','confirmation-lifecycle-driver-r3.py','completed')]:
 with tempfile.TemporaryDirectory(prefix='lumen256-host-caller-') as temp:
  group=Path(temp)/'group';group.mkdir();runner=Path(temp)/'runner';(runner/'tmp').mkdir(parents=True)
  state=copy.deepcopy(original);window=state['confirmationWindow'];window['runner']=str(runner);window.pop('hostCheckCompleted',None)
  gate=json.loads(rawvalue('gate'));run=gate['runID'].lower();nonce=gate['nonce'].lower();stem='Lumen-confirmation-window-'+run+'-'+nonce
  gatepath=group/(stem+'.json');gatepath.write_bytes(rawvalue('gate'));ackpath=group/(stem+'-ack.json');ack=base64.b64decode(window['ackBytes']['base64'],validate=True);ackpath.write_bytes(ack)
  tracepath=group/('Lumen-confirmation-lifecycle-'+run+'-'+nonce+'.json');checkpath=tracepath.with_suffix('.check-1.json');trace=json.loads(rawvalue('trace'));trace['checks'][0]['file']=str(checkpath);check=json.loads(rawvalue('check'))
  if label=='native-check-rejected':check['check']['status']='synthetic-rejected'
  checkraw=json.dumps(check,sort_keys=True).encode();checkpath.write_bytes(checkraw);trace['checks'][0]['bytes']=len(checkraw);trace['checks'][0]['sha256']=hashlib.sha256(checkraw).hexdigest();tracepath.write_text(json.dumps(trace))
  for phase in ['presented','dismissed','checked']:
   if label=='checked-marker-missing' and phase=='checked':continue
   (runner/'tmp'/('Lumen-confirmation-lifecycle-ui-'+nonce+'-'+phase+'.json')).write_bytes(rawvalue(phase))
  if label=='wrong-ack':ackpath.write_bytes(b'{}')
  if label=='truthy-nonboolean-not-complete':window['hostCheckCompleted']={'synthetic':True}
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
  if expected in ['completed','repeat']:
   assert failure is None and calls==['protected-after-check','origin-after-check','checked-relay'] and window['hostCheckCompleted'] is True
   assert isinstance(window['checked'],dict) and window['checked']['versions']
   assert window['relays'][-1]['value']['phase']=='checked' and window['relays'][-1]['value']['checkOrdinal']=='1'
   if expected=='repeat':
    calls.clear();env['confirmation_gate'](group);assert calls==[] and isinstance(window['checked'],dict) and window['hostCheckCompleted'] is True
  elif expected=='rejected':assert failure is not None and calls==[] and window.get('hostCheckCompleted') is not True
  else:assert failure is None and calls==[] and window.get('hostCheckCompleted') is not True
  rows.append({'case':label,'actualSource':file,'expected':expected,'failure':failure,'actualObserveExecuted':True,'completionFlag':window.get('hostCheckCompleted'),'checkedMarkerStillDictionary':isinstance(window.get('checked'),dict),'postCheckStages':calls,'status':'PASS'})
assert not queries
sources={}
for n in ['confirmation-lifecycle-driver-r2.py','confirmation-lifecycle-driver-r3.py','confirmation-lifecycle-protocol-r1.py','confirmation-window-evidence-r3.py']:
 raw=(B/n).read_bytes();sources[n]={'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
r={'status':'PASS7actual whole confirmation_gate+observe caller paths with real protocol/regular-file readers and native255-derived fixture data','count':len(rows),'cases':rows,'sources':sources,'realProcessQueries':queries,'scope':'Real actual observed-marker storage and protocol validators execute in unique TemporaryDirectory files, with native255 JSON only as retained fixture input. Trace header file/hash adapted to fixture copy; no native/fresh process proof. Only protection/origin/publisher persistence dependencies injected and explicitly recorded. Old whole caller reproduces marker-dictionary early return. New completes once, retains checked dictionary, repeated call skips duplicate stages; wrong ack/rejected nativeCheck/pending marker never publish. All fixture files automatically removed.','checkedAt':time.time()};p=B/'source256-host-caller-controls-r2.json';assert not p.exists();p.write_text(json.dumps(r,indent=2)+'\n');print(r['status'])
