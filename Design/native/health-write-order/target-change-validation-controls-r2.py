"""Isolated retained-evidence injection controls; no device/defaults writes."""
import base64
import copy
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import traceback
BASE=Path(__file__).resolve().parent

def module(name,file):
 spec=importlib.util.spec_from_file_location(name,BASE/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
v=module('retained_controls','legacy-target-change-validation-r2.py')
ob=module('observation_controls','legacy-target-change-observation-r1.py')
h=module('common_controls','health-mixed-ineligible-evidence-r1.py')
parent=BASE/'health-legacy-settings-erase-data-source225r1-host-audit.json'
state=json.loads(parent.read_bytes());initial=state['boundaries'][0]
protected={'current':initial['currentTree'],'prior':initial['priorTree'],'provider':state['provider'],
 'residuals':{k:[] for k in ['LumenData.restore-*','LumenData.retired-*','Lumen-reset-fixture-*']}}
fixture={'historicalSyntheticSource':parent.name,'historicalSHA256':hashlib.sha256(parent.read_bytes()).hexdigest(),
 'scope':'Actual historical synthetic tree/selection replay as isolated validator input, not current target-change native proof',
 'protected':protected,'selection':state['selection'],'pid':state['initialPID']}
clock=[0.0];sink={};sequence=[h.DATA,ob.NEW,ob.NEW,ob.NEW]
class Fake:
 DATA=h.DATA;sha=staticmethod(h.sha)
 @staticmethod
 def read(path,limit):
  meals=sequence.pop(0) if len(sequence)>1 else sequence[0]
  return plistlib.dumps({ob.KEYS[0]:meals,ob.KEYS[1]:h.DATA,'lumen.health.connected':False})
ob.wait(Path('synthetic-readonly-not-opened.plist'),Fake,sink,lambda:None,clock=lambda:clock[0],sleep=lambda dt:clock.__setitem__(0,clock[0]+dt))
fixture['persistence']=sink
rows=[]
def trial(name,kind,change,expected):
 data=copy.deepcopy(fixture[kind]);change(data)
 try:
  if kind=='protected':v.protected(data,fixture['protected'],h)
  elif kind=='persistence':v.persistence(data,h,ob)
  else:v.selection(data,fixture['protected']['provider'],fixture['pid'],h)
  actual=True;error=None
 except BaseException:actual=False;error=traceback.format_exc()
 assert actual==expected,name
 rows.append({'case':name,'kind':kind,'expectedAccept':expected,'actualAccept':actual,'injected':data,'error':error})
noop=lambda x:None
trial('exact protected replay','protected',noop,True)
trial('exact old-to-new samples','persistence',noop,True)
trial('exact selected replay','selection',noop,True)
file=next(iter(protected['current']['files']))
trial('changed raw protected bytes','protected',lambda d:d['current']['files'][file].update(base64=base64.b64encode(b'changed').decode()),False)
trial('changed protected metadata','protected',lambda d:d['current']['metadata']['files'][file]['identity'].update(st_ino=1),False)
trial('changed prior root identity','protected',lambda d:d['prior']['rootIdentity'].update(st_ino=1),False)
trial('unexpected receipt','protected',lambda d:d['current']['files'].update({'receipt.json':h.row(b'{}')}),False)
trial('unexpected stage','protected',lambda d:d['residuals']['LumenData.restore-*'].append('unexpected'),False)
trial('provider identity changed','protected',lambda d:d['provider']['identity'].update(st_ino=1),False)
trial('wrong typed sample','persistence',lambda d:d['samples'][0]['fixed'][ob.KEYS[0]].update(type='str'),False)
trial('wrong known sample bytes','persistence',lambda d:d['samples'][0]['fixed'][ob.KEYS[0]].update(base64=base64.b64encode(b'unknown').decode()),False)
trial('workout changed','persistence',lambda d:d['samples'][0]['fixed'][ob.KEYS[1]].update(sha256='0'*64),False)
trial('Health connected','persistence',lambda d:d['samples'][0].update(healthConnected=True),False)
trial('sample error hidden by PASS','persistence',lambda d:d['samples'][0].update(error='injected observation failure'),False)
trial('time regressed','persistence',lambda d:d['samples'][-1].update(elapsed=-1),False)
trial('deadline exceeded','persistence',lambda d:d['samples'][-1].update(completedElapsed=10.1),False)
trial('insufficient stable span','persistence',lambda d:d['samples'][-1].update(completedElapsed=d['samples'][-2]['completedElapsed']),False)
trial('acceptance time inconsistent','persistence',lambda d:d.update(acceptedElapsed=0),False)
trial('old resets stable streak','persistence',lambda d:d['samples'][-2].update(classification='old',fixed=copy.deepcopy(d['samples'][0]['fixed'])),False)
trial('source selected bytes changed','selection',lambda d:d['source'].update(base64=base64.b64encode(b'changed').decode()),False)
trial('source PID changed','selection',lambda d:d['source']['owner'].update(pid=1),False)
trial('workspace owner marker changed','selection',lambda d:next(iter(d['workspaces'].values()))['owner'].update(pid=1),False)
# Only actual state.preflight.app is metadata-only. The checker binds this
# argument to h.verify_inputs(actual frozen source/build/binary) before traversal.
app={'bytes':12,'sha256':h.sha(b'known binary'),'base64':None}
raw=b'known payload';payload=h.row(raw)
def metadata_trial(name,value,expected):
 try:v.all_payloads(value,h,app);actual=True;error=None
 except BaseException:actual=False;error=traceback.format_exc()
 assert actual==expected,name
 rows.append({'case':name,'kind':'metadata-payload traversal','expectedAccept':expected,'actualAccept':actual,'injected':value,'error':error})
metadata_trial('exact metadata and nested payload',{'preflight':{'app':app},'retained':[payload]},True)
metadata_trial('null payload elsewhere',{'retained':app},False)
metadata_trial('nested app spoof',{'retained':{'preflight':{'app':app}}},False)
metadata_trial('metadata bytes wrong',{'preflight':{'app':{**app,'bytes':13}}},False)
metadata_trial('metadata digest wrong',{'preflight':{'app':{**app,'sha256':'0'*64}}},False)
metadata_trial('metadata raw unexpectedly retained',{'preflight':{'app':{**app,'base64':payload['base64']}}},False)
metadata_trial('payload digest wrong',{'retained':{**payload,'sha256':'0'*64}},False)
metadata_trial('malformed base64',{'retained':{**payload,'base64':'%%%'}},False)
metadata_trial('array null not exempt',{'rows':[app]},False)
fixture['metadataExpected']=app
archive=BASE/'source228-retained-validation-controls-r2-fixtures.json.gz'
data=json.dumps({'fixture':fixture,'trials':rows},sort_keys=True).encode();archive.write_bytes(gzip.compress(data,mtime=0))
result={'status':'PASS isolated31retained evidence and metadata-path replay/injection controls; no native/current-state proof','runnerSHA256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'cases':[{k:r[k] for k in ['case','kind','expectedAccept','actualAccept']} for r in rows],
 'fixtureArchive':archive.name,'decodedBytes':len(data),'decodedSHA256':hashlib.sha256(data).hexdigest(),'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest()}
(BASE/'source228-retained-validation-controls-r2.json').write_text(json.dumps(result,indent=2)+'\n');print(result['status'])
