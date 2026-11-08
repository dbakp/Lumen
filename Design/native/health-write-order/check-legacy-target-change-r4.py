"""Readonly complete actual target-change verification, retained and final live."""
import argparse
import base64
import importlib.util
import json
from pathlib import Path
BASE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('target_check_evidence',BASE/'legacy-target-change-evidence-r2.py')
e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h
v=e.e.module('target_retained_validation','legacy-target-change-validation-r3.py')
p=argparse.ArgumentParser();p.add_argument('prefix');a=p.parse_args();assert Path(a.prefix).name==a.prefix
out=h.load(BASE/(a.prefix+'-outcome.json'));assert out['driverExit']==out['nativeExit']==0 and out['hostError'] is None
assert out['status'].startswith('PASS actual native1/0/0')
for key in ['outcomePersistenceErrors','finalizationPersistenceErrors','nativeFinalizationError','retainerException','salvageException','emergencyOutcomePersistenceError','failure']:
 assert not out.get(key),key
assert not list(BASE.glob(a.prefix+'*emergency.json'))
state=h.load(BASE/(a.prefix+'-host-audit.json'));inputs=h.verify_inputs(state['source'],state['build'])
assert state['preflight']==inputs, 'Retained preflight must bind actual reviewed source/build/app/test inputs'
assert state['device']==h.DEVICE and len(state['boundaries'])==len(state['messages'])==7
assert [r['phase'] for r in state['boundaries']]==e.PHASES
first=state['boundaries'][0]['protected'];v.protected(first,first,h)
assert len(first['current']['files'])==len(first['prior']['files'])==13
assert first['provider']==state['provider'];v.selection(state['selection'],state['provider'],state['appPID'],h)
v.selection(state['freshSelection'],state['provider'],state['appPID'],h)
assert set(state['selection']['workspaces']).isdisjoint(state['freshSelection']['workspaces'])
assert not {'meals.json','workouts.json'}&set(first['current']['files'])
for index,row in enumerate(state['boundaries']):
 assert row['status']=='PASS'
 value=e.check_state(row['observation'],state['started'],state['runID'],state['appPID'])
 assert value['sequence']==e.COUNTS[index] and value['status']==e.STATUSES[index]
 assert state['messages'][index]['value']=={**{k:value[k] for k in ['runID','pid','sessionID','captureID','sequence']},'phase':'host-'+row['phase']}
 # Recheck actual trace rows without replacing retained data with live data.
 expected=[[],['open','ready'],['open','ready','acquire'],['open','ready','acquire','acquire'],['open','ready','acquire','acquire','closed'],['open','ready','acquire','acquire','closed','open','ready'],['open','ready','acquire','acquire','closed','open','ready','closed']][index]
 assert [r['event'] for r in row['originEvents']]==expected
 assert all(r['sessionID']==state['oldSession'] for r in row['originEvents'][:5])
 assert all(r['sessionID']==state['boundaries'][5]['observation']['sessionID'] for r in row['originEvents'][5:])
 endpoints=row['endpoints'] if index in [4,6] else [row]
 if index in [4,6]:
  assert len(endpoints)==2 and endpoints[1]['monotonic']-endpoints[0]['monotonic']>=3
  selection=state['selection'] if index==4 else state['freshSelection']
  assert row['ownerClosureSamples'][-1]['workspaces']=={}
  for endpoint in endpoints:v.cleanup(endpoint['cleanup'],selection)
 for endpoint in endpoints:
  v.protected(endpoint['protected'],first,h)
  v.fixed(endpoint['fixed'],h.DATA if index<2 else e.obs.NEW,h,e.obs)
  assert endpoint['process']['pid']==state['appPID']
  if 'selected' in endpoint:
   selection=state['freshSelection'] if index==5 else state['selection']
   assert endpoint['selected']==selection
 if index==0:
  v.bootstrap(row['initialBootstrap'],row,h)
  v.bootstrap_context(row['finalBootstrapContext'],row,h)
  v.protected(row['postBootstrapProtected'],first,h)
 if index==2:v.persistence(row['preferencePersistence'],h,e.obs)
retained=out['retention'];assert not retained['errors']
assert retained==h.load(BASE/(a.prefix+'-retention-state.json'))
assert retained['images']==h.load(BASE/(a.prefix+'-images.json'))
assert retained['readbacks']==h.load(BASE/(a.prefix+'-readbacks.json'))
assert retained['summary']==out['summary']==h.load(BASE/(a.prefix+'-summary.json'))
assert retained['summaryAvailable'] is True
import gzip
for query in retained['queries']:
 assert query['exitCode']==0
 for stream in ['stdout','stderr']:
  fact=query[stream];raw=gzip.decompress(h.read(BASE/fact['retained'],4*1024*1024))
  assert fact['retainedExact'] is True and len(raw)==fact['bytes'] and h.sha(raw)==fact['sha256']
fact=retained['log'];raw=gzip.decompress(h.read(BASE/fact['retained'],8*1024*1024))
assert fact['retainedExact'] is True and len(raw)==fact['bytes'] and h.sha(raw)==fact['sha256']
assert [retained['summary'][k] for k in ['passedTests','failedTests','skippedTests']]==[1,0,0]
assert len(retained['images'])==13 and len(retained['readbacks'])==1
names=[]
for row in retained['images']+retained['readbacks']:
 data=h.read(BASE/row['file'],4*1024*1024);assert len(data)==row['bytes'] and h.sha(data)==row['sha256']
 if row in retained['images']:
  label=row['metadata']['suggestedHumanReadableName']
  matches=[suffix for suffix in e.IMAGES if label.startswith('health-legacy-target-change-'+suffix+'_')]
  assert len(matches)==1;names+=matches
assert set(names)==set(e.IMAGES)
helper=h.load(BASE/retained['readbacks'][0]['file']);assert helper['phase']=='completed'
assert helper['scope']=='actual-legacy-target-change-after-ready-before-confirmation'
args=helper['launchArguments']
for flag,expected in [('-health-legacy-target-change-ui','ready'),('-health-legacy-target-change-run',state['runID']),('-health-legacy-reset-run',state['runID']),('-health-legacy-origin-ui','data'),('-health-backup-case','legacy')]:
 assert args.count(flag)==1 and args[args.index(flag)+1]==expected
assert not helper.get('failure')
startup=[r for r in helper['observations'] if r['phase']=='native-before-selection-tap']
assert len(startup)==1 and startup[0]['identifier']=='startHealthRecoveryCheck'
assert startup[0]['beforeTouchHittable'] is True and startup[0]['beforeTouchEnabled'] is True
assert [r['phase'] for r in helper['observations'] if 'probeValue' in r]==e.PHASES
v.all_payloads(state,h,inputs['app'])
previous=-1
for native in state['nativeStates']:
 data=v.payload(native,h,128*1024);assert json.loads(data)==native['value']
 value=e.check_state(native['value'],state['started'],state['runID'],state['appPID'])
 assert value['sequence']>=previous;previous=value['sequence']
assert state['nativeStates'][-1]['value']==state['boundaries'][-1]['observation']
# Final live endpoint is separate from actual retained native/host endpoints.
live={'status':'OBSERVING final live endpoint; no acceptance yet','source':state['source'],'build':state['build']}
path=BASE/(a.prefix+'-live-audit.json')
def persist():path.write_text(json.dumps(live,indent=2)+'\n')
try:
 group=h.container('group.com.dbakp.lumen');native=state['nativeStates'][-1]
 live['nativeState']={'file':native['file'],**h.row(h.read(native['file'],128*1024))};persist()
 assert live['nativeState']['base64']==native['base64']
 live['installed']=h.installed(state['build']);live['processCommand']=h.subprocess.check_output(['ps','-p',str(state['appPID']),'-o','comm='],text=True).strip();persist()
 assert Path(live['processCommand'])==h.container('app')/'Lumen'
 live['protected']={};e.protected(group,live['protected'],first)
 live['fixed']={};e.obs.sample(h.container('data')/'Library/Preferences/com.dbakp.lumen.plist',h,live['fixed'],persist,[e.obs.NEW])
 live['oldCleanup']=e.e.no_owned(state['selection'],state['appPID']);persist()
 live['freshCleanup']=e.e.no_owned(state['freshSelection'],state['appPID']);persist()
 live['originEvents']=e.origin_trace(group,6,state['oldSession'],state['boundaries'][5]['observation']['sessionID'])
 live['status']='PASS final live protected/current/prior/newer fixed/provider/installed/owners endpoint; bounded only'
finally:persist()
print(json.dumps({'status':'PASS actual target-change retained facts and final live endpoint; visual/root/independent review separate','inputs':inputs['inputs'],'boundaries':7,'originals':13,'helperBytes':retained['readbacks'][0]['bytes'],'nativeStates':len(state['nativeStates'])}))
