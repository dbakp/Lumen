"""Two later failed-case observations only; no app launch/defaults mutation/cleanup."""
from pathlib import Path
import importlib.util,json,time,os,traceback
B=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('failed247',B/'confirmation-target-evidence-r1.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h
p=e.e.module('failed247process','target-postrun-process-r1.py');state=json.loads((B/'health-legacy-confirmation-data-source247r1-driver-observations.json').read_bytes());first=state['boundaries'][0]['protected'];output=B/'source247-post-failure-readonly-diagnostic-r1.json';assert not output.exists()
r={'status':'RECORDING later endpoints; original failed case remains failed','samples':[],'physicalPhoneActions':False,'started':time.time()}
def persist():output.write_text(json.dumps(r,indent=2)+'\n')
persist()
try:
 group=Path(state['nativeStates'][-1]['file']).parent;data=h.container('data');assert str(data)==state['appData']
 for ordinal in range(2):
  if ordinal:time.sleep(.25)
  row={'monotonic':time.monotonic(),'process':{}};r['samples'].append(row);persist();p.observe(state['appPID'],state['boundaries'][0]['installed']['path'],row['process'],persist)
  row['protected']={}
  for name,path in [('current',group/'LumenData'),('prior',group/'LumenData.previous')]:
   row['protected'][name]={};e.e.observe_tree(path,row['protected'][name])
  row['protected']['provider']=h.provider();row['protected']['residuals']={pattern:[str(x) for x in group.glob(pattern)] for pattern in first['residuals']}
  e.v.protected(row['protected'],first,h);persist()
  row['fixed']={};e.obs.sample(data/'Library/Preferences/com.dbakp.lumen.plist',h,row['fixed'],persist,[h.DATA]);e.v.fixed(row['fixed'],h.DATA,h,e.obs)
  row['installed']=h.installed(state['build']);assert row['installed']==state['boundaries'][0]['installed']
  native=Path(state['nativeStates'][-1]['file']);row['native']={'file':str(native),**h.row(h.read(native,128*1024))};value=json.loads(h.read(native,128*1024));assert value==state['nativeStates'][-1]['value'];row['nativeValue']=value
  row['ownedWorkspaces']=h.owned(state['appPID']);row['caseRoots']={root:os.path.lexists(root) for key in ['selection'] for root in state[key]['workspaces']};row['originEvents']=h.events(group);row['completedMonotonic']=time.monotonic();persist()
 r.update(status='RECORDED later two process/current13+prior13/bothlegacyData42/provider/installed/native3/heldsourceowner endpoints; original native0/1/0 and checker1 unchanged',scope='No targetmutation/Recover/stalerejection/freshcommit/Back/closure acceptance. Two sampled endpoints only, no continuousabsence/globalFD/exitcause inference; no mutation/relaunch/build/reset/cleanup.',finished=time.time());persist()
except BaseException:r.update(status='FAILED later diagnostic',error=traceback.format_exc(),finished=time.time());persist();raise
print(json.dumps({'status':r['status'],'modes':[x['process']['mode'] for x in r['samples']],'owned':[len(x['ownedWorkspaces']) for x in r['samples']]}))
