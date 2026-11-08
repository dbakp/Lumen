"""Two later failed-case observations only; no app launch/defaults mutation/cleanup."""
from pathlib import Path
import importlib.util,json,time,os,traceback
B=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('failed239',B/'target-string-evidence-r1.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h
p=e.e.module('failed239process','target-postrun-process-r1.py');state=json.loads((B/'health-legacy-target-change-string-source239r1-driver-observations.json').read_bytes());first=state['boundaries'][0]['protected'];output=B/'source239-post-failure-readonly-diagnostic-r1.json';assert not output.exists()
r={'status':'RECORDING later endpoints; original failed case remains failed','samples':[],'physicalPhoneActions':False,'started':time.time()}
def persist():output.write_text(json.dumps(r,indent=2)+'\n')
persist()
try:
 group=Path(state['nativeStates'][-1]['file']).parent;data=h.container('data');assert str(data)==state['appData']
 for ordinal in range(2):
  if ordinal:time.sleep(.25)
  row={'monotonic':time.monotonic(),'process':{}};r['samples'].append(row);persist();p.observe(state['appPID'],state['boundaries'][0]['installed']['path'],row['process'],persist)
  row['protected']={};e.protected(group,row['protected'],first);persist()
  row['fixed']={};e.obs.sample(data/'Library/Preferences/com.dbakp.lumen.plist',h,row['fixed'],persist,[e.obs.NEW]);e.v.fixed(row['fixed'],e.obs.NEW,h,e.obs)
  row['installed']=h.installed(state['build']);assert row['installed']==state['boundaries'][0]['installed']
  native=Path(state['nativeStates'][-1]['file']);row['native']={'file':str(native),**h.row(h.read(native,128*1024))};value=json.loads(h.read(native,128*1024));assert value==state['nativeStates'][-1]['value'];row['nativeValue']=value
  row['ownedWorkspaces']=h.owned(state['appPID']);row['caseRoots']={root:os.path.lexists(root) for root in state['selection']['workspaces']};row['originEvents']=h.events(group);row['completedMonotonic']=time.monotonic();persist()
 r.update(status='RECORDED later two process/protected13+13/newmealString66+workoutString70/provider/installed/native7/owner endpoints; original native0/1/0 and checker1 unchanged',scope='No actual staleRecover/freshcommit/finalBack/UIclosure acceptance, no continuous absence/globalFD/exitcause inference; no mutation/relaunch/build/reset/cleanup.',finished=time.time());persist()
except BaseException:r.update(status='FAILED later diagnostic',error=traceback.format_exc(),finished=time.time());persist();raise
print(json.dumps({'status':r['status'],'modes':[x['process']['mode'] for x in r['samples']],'owned':[len(x['ownedWorkspaces']) for x in r['samples']]}))
