"""Isolated initial-bootstrap fake-clock/tempplist and retained-validator controls."""
import base64,copy,gzip,hashlib,importlib.util,json,os,plistlib,stat,tempfile,time,traceback
from pathlib import Path
BASE=Path(__file__).resolve().parent

def module(name,file):
 s=importlib.util.spec_from_file_location(name,BASE/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
h=module('bootstrap_common','health-mixed-ineligible-evidence-r1.py')
ob=module('bootstrap_observer','legacy-target-bootstrap-observation-r1.py')
v=module('bootstrap_validation','legacy-target-change-validation-r3.py')
e=module('bootstrap_schema','legacy-target-change-evidence-r2.py')
raw=Path(tempfile.mkdtemp(prefix='LumenTargetBootstrap230-'));rows=[];raw_payloads={}
rootid=dict(zip(h.FIELDS,[11,1,stat.S_IFDIR|0o700,2,64,1]))
meta=dict(zip(h.FIELDS,[12,1,stat.S_IFREG|0o600,1,8,1]))
checkpoint=json.dumps({'scope':'synthetic comparator fixture only'}).encode();meta['st_size']=len(checkpoint)
provider={'file':'/synthetic/source.json','identity':meta,'bytes':len(h.DATA),'sha256':h.sha(h.DATA)}
installed={'path':'/synthetic/Lumen.app/Lumen','bytes':12,'sha256':h.sha(b'known binary')}
reference={'scope':'Synthetic comparator metadata, not a native checkpoint','nativeCheckpoint':{'file':'/synthetic/checkpoint.json','identity':meta,**h.row(checkpoint)},'process':{'executable':installed['path']},'installed':installed,'protected':{'current':{'rootIdentity':rootid},'prior':{'rootIdentity':rootid},'provider':provider}}
context_value={'native':{'file':reference['nativeCheckpoint']['file'],**h.row(checkpoint)},'nativeIdentity':meta,
 'processCommand':installed['path'],'currentRootIdentity':rootid,'priorRootIdentity':rootid,'provider':provider,'installed':installed,'ownedPaths':[]}
sequence_cases=[('missing-partial-old',[(None,None),(h.DATA,None),(h.DATA,h.DATA)],True),('already-old',[(h.DATA,h.DATA)],True),
 ('file-absent-then-old',[(None,None),(h.DATA,h.DATA)],True),('symlink',[(h.DATA,h.DATA)],False),('identity-race',[(h.DATA,h.DATA)],False),('never-ready',[(None,None)],False),('changed-meals',[(b'changed',h.DATA)],False),('changed-workouts',[(h.DATA,b'changed')],False),
 ('unsupported',[(dict(synthetic='unsupported'),h.DATA)],False),('oversize',[(b'x'*4097,h.DATA)],False),
 ('Health-connected',[(h.DATA,h.DATA)],False),('malformed',[(None,None)],False),('whole-plist-oversize',[(None,None)],False),
 ('lost-context',[(h.DATA,h.DATA)],False),('fleeting-old-reset',[(h.DATA,h.DATA),(None,h.DATA),(h.DATA,h.DATA)],True)]
valid=None
for name,sequence,expected in sequence_cases:
 folder=raw/name;folder.mkdir();path=folder/'com.dbakp.lumen.plist';clock=[0.0];index=[0];sink={};persisted=[]
 def persist():persisted.append(json.dumps(sink))
 def context(sink_context):
  sink_context.update(copy.deepcopy(context_value));i=index[0];index[0]+=1
  if name=='lost-context' and i==1:
   sink_context['processCommand']='/synthetic/unexpected';raise AssertionError('actual context guard rejected phase/process mismatch')
  a,b=sequence[min(i,len(sequence)-1)]
  values={'lumen.health.connected':name=='Health-connected'}
  if a is not None:values[ob.KEYS[0]]=a
  if b is not None:values[ob.KEYS[1]]=b
  blob=(b'not plist' if name=='malformed' else b'x'*(256*1024+1) if name=='whole-plist-oversize' else plistlib.dumps(values))
  if name=='file-absent-then-old' and i==0:
   raw_payloads[name+'-'+str(i)]={'fixtureState':'leaf absent'};return
  if name=='symlink':
   target=folder/'known-target.plist';target.write_bytes(blob);path.symlink_to(target.name)
  else:path.write_bytes(blob)
  raw_payloads[name+'-'+str(i)]=base64.b64encode(blob).decode()
 class Probe:
  DATA=h.DATA;sha=staticmethod(h.sha);identity=staticmethod(h.identity)
  @staticmethod
  def read(p,limit):
   data=h.read(p,limit)
   if name=='identity-race':Path(p).write_bytes(data+b'\n')
   return data
 try:ob.wait(path,Probe,sink,persist,context,clock=lambda:clock[0],sleep=lambda dt:clock.__setitem__(0,clock[0]+dt));actual=True;error=None
 except BaseException:actual=False;error=traceback.format_exc()
 assert actual==expected,name
 assert persisted and sink['samples']
 if actual:
  v.bootstrap(sink,reference,h)
  if valid is None:valid=copy.deepcopy(sink)
 rows.append({'case':name,'kind':'actual isolated observer','expectedAccept':expected,'actualAccept':actual,'samples':sink,'error':error,'persistenceCalls':len(persisted)})

def retained(name,change,expected=False):
 d=copy.deepcopy(valid);change(d)
 try:v.bootstrap(d,reference,h);actual=True;error=None
 except BaseException:actual=False;error=traceback.format_exc()
 assert actual==expected,name
 rows.append({'case':name,'kind':'retained bootstrap validator','expectedAccept':expected,'actualAccept':actual,'samples':d,'error':error})
retained('retained valid',lambda d:None,True)
retained('retained hidden sample error',lambda d:d['samples'][0].update(error='injected'))
retained('retained changed bytes',lambda d:d['samples'][-1]['fixed']['keys'][ob.KEYS[0]].update(base64=base64.b64encode(b'changed').decode()))
retained('retained missing resets streak',lambda d:d['samples'][-2].update(fixed=copy.deepcopy(d['samples'][0]['fixed'])))
retained('retained regressed time',lambda d:d['samples'][-1].update(elapsed=-1))
retained('retained deadline',lambda d:d['samples'][-1].update(completedElapsed=10.1))
retained('retained context byte change',lambda d:d['samples'][0]['context']['native'].update(sha256='0'*64))
retained('retained root identity change',lambda d:d['samples'][0]['context']['currentRootIdentity'].update(st_ino=1))
retained('retained provider change',lambda d:d['samples'][0]['context']['provider'].update(sha256='0'*64))
retained('retained installed change',lambda d:d['samples'][0]['context']['installed'].update(sha256='0'*64))
retained('retained owned worker',lambda d:d['samples'][0]['context'].update(ownedPaths=['/synthetic/owned']))
# Actual source schema with a synthetic complete initial-only state; no UI credit.
run='68802D08-9C0A-49E7-80DF-D38DE80927C9'
fact={'present':True,'type':'Foundation.Data','bytes':len(h.DATA),'sha256':h.sha(h.DATA),'payload':base64.b64encode(h.DATA).decode()}
state={'verificationProtocol':e.PROTOCOL,'runID':run,'pid':1,'at':2,'sequence':0,'events':[],'sessionID':'','captureID':'',
 'singleUseConsumed':False,'knownKeyWritten':False,'failed':False,'healthConnected':False,'status':'before-selection','bootstrapNativeChecked':True,
 'bootstrapObservation':{'runID':run,'pid':1,'at':1,'healthConnected':False,'fixed':{k:{'persisted':fact,'effective':fact} for k in ob.KEYS},
 'mealsLeaf':{'missing':True,'exists':False,'errno':2,'mode':0},'workoutsLeaf':{'missing':True,'exists':False,'errno':2,'mode':0}}}
def schema(name,change,expected=False):
 d=copy.deepcopy(state);change(d)
 try:e.check_state(d,0,run,1);actual=True;error=None
 except BaseException:actual=False;error=traceback.format_exc()
 assert actual==expected,name
 rows.append({'case':name,'kind':'actual source schema synthetic state','expectedAccept':expected,'actualAccept':actual,'state':d,'error':error})
schema('schema exact UI checkpoint',lambda d:None,True)
schema('schema prepared not checked',lambda d:d.update(status='prepared'))
schema('schema nonce mismatch',lambda d:d['bootstrapObservation'].update(runID='different'))
schema('schema PID mismatch',lambda d:d['bootstrapObservation'].update(pid=2))
schema('schema Health connected',lambda d:d['bootstrapObservation'].update(healthConnected=True))
schema('schema current leaf exists',lambda d:d['bootstrapObservation']['mealsLeaf'].update(missing=False,exists=True,errno=0,mode=stat.S_IFREG|0o600))
schema('schema arbitrary phase',lambda d:d.update(status='unexpected'))
schema('schema missing native key',lambda d:d['bootstrapObservation']['fixed'].pop(ob.KEYS[0]))
encoded=json.dumps({'scope':'Isolated fixtures only; no current native/LocalStore/latency proof','rawRoot':str(raw),'reference':reference,'trials':rows,'rawPlists':raw_payloads},sort_keys=True).encode()
archive=BASE/'source230-bootstrap-controls-r1-fixtures.json.gz';archive.write_bytes(gzip.compress(encoded,mtime=0))
result={'status':'PASS isolated bootstrap observer/retained/schema controls; no native proof','rawRoot':str(raw),'rawRetainedUntilExactGithub':True,'count':len(rows),'cases':[{k:r[k] for k in ['case','kind','expectedAccept','actualAccept']} for r in rows],
 'runnerSHA256':h.sha(Path(__file__).read_bytes()),'fixtureArchive':archive.name,'decodedBytes':len(encoded),'decodedSHA256':h.sha(encoded),'bytes':archive.stat().st_size,'sha256':h.sha(archive.read_bytes())}
(BASE/'source230-bootstrap-controls-r1.json').write_text(json.dumps(result,indent=2)+'\n');print(result['status'],len(rows),str(raw))
