"""Readonly complete actual target-change result verification; no producer."""
import argparse
import base64
import importlib.util
import json
from pathlib import Path
BASE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('target_check_evidence',BASE/'legacy-target-change-evidence-r1.py')
e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h
p=argparse.ArgumentParser();p.add_argument('prefix');a=p.parse_args()
assert Path(a.prefix).name==a.prefix
out=h.load(BASE/(a.prefix+'-outcome.json'));assert out['driverExit']==out['nativeExit']==0 and out['hostError'] is None
assert out['status'].startswith('PASS actual native1/0/0')
state=h.load(BASE/(a.prefix+'-host-audit.json'))
inputs=h.verify_inputs(state['source'],state['build'])
assert state['device']==h.DEVICE and len(state['boundaries'])==7
assert [r['phase'] for r in state['boundaries']]==e.PHASES
for index,row in enumerate(state['boundaries']):
 assert row['status']=='PASS'
 value=e.check_state(row['observation'],state['started'],state['runID'],state['appPID'])
 assert value['sequence']==e.COUNTS[index] and value['status']==e.STATUSES[index]
 assert state['messages'][index]['value']=={**{k:value[k] for k in ['runID','pid','sessionID','captureID','sequence']},'phase':'host-'+row['phase']}
 if index in [4,6]:
  assert row['endpoints'][1]['monotonic']-row['endpoints'][0]['monotonic']>=3
  assert all(x['cleanup']['rootsAbsent'] and x['cleanup']['hostDeletedWorkspace'] is False for x in row['endpoints'])
retained=out['retention'];assert not retained['errors']
assert [retained['summary'][k] for k in ['passedTests','failedTests','skippedTests']]==[1,0,0]
assert len(retained['images'])==13 and len(retained['readbacks'])==1
for row in retained['images']+retained['readbacks']:
 data=h.read(BASE/row['file'],4*1024*1024);assert len(data)==row['bytes'] and h.sha(data)==row['sha256']
helper=h.load(BASE/retained['readbacks'][0]['file']);assert helper['phase']=='completed'
assert [r['phase'] for r in helper['observations'] if 'probeValue' in r]==e.PHASES
# Every original attachment remains bound; human/critic image reading is separate.
for native in state['nativeStates']:
 data=base64.b64decode(native['base64'],validate=True)
 assert len(data)==native['bytes'] and h.sha(data)==native['sha256'] and json.loads(data)==native['value']
 e.check_state(native['value'],state['started'],state['runID'],state['appPID'])
assert state['boundaries'][2]['preferencePersistence']['status'].startswith('PASS bounded')
assert state['boundaries'][3]['observation']['events'][7]['publishedMessage']==e.MESSAGE
assert h.provider()==state['provider']
print(json.dumps({'status':'PASS complete actual target-change retained boundaries; visual/root/independent review separate','inputs':inputs['inputs'],'boundaries':7,'originals':13,'helperBytes':retained['readbacks'][0]['bytes'],'nativeStates':len(state['nativeStates'])}))
