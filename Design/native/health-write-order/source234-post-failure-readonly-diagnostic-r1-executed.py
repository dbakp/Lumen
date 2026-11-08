"""Later sampled failed-case facts; no relaunch, preferences write or cleanup."""
import importlib.util,json,os,time,traceback
from pathlib import Path
B=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('failure234diagnostic',B/'legacy-target-change-evidence-r5.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e)
p=e.e.module('failure234process','target-postrun-process-r1.py');h=e.h
state=json.loads((B/'health-legacy-target-change-data-source234r1-driver-observations.json').read_bytes())
path=B/'source234-post-failure-readonly-diagnostic-r1.json';assert not path.exists()
result={'status':'RECORDING later readonly facts; original failed case not accepted','samples':[],'newAppBuilds':0,'newNativeRuns':0,'physicalPhoneActions':False,'started':time.time()}
def persist():path.write_text(json.dumps(result,indent=2)+'\n')
persist()
try:
 group=Path(state['nativeStates'][-1]['file']).parent;first=state['boundaries'][0]['protected']
 assert str(h.container('data'))==state['appData']
 for ordinal in range(2):
  if ordinal:time.sleep(.25)
  row={'monotonic':time.monotonic(),'process':{}};result['samples'].append(row);persist()
  p.observe(state['appPID'],state['boundaries'][0]['installed']['path'],row['process'],persist)
  row['installed']=h.installed(state['build']);persist();assert row['installed']==state['boundaries'][0]['installed']
  native=Path(state['nativeStates'][-1]['file']);row['native']={'file':str(native),**h.row(h.read(native,128*1024))};persist()
  value=json.loads(h.read(native,128*1024));e.check_state(value,state['started'],state['runID'],state['appPID'])
  row['nativeValue']=value;persist();assert value['sequence'] in [13,14]
  row['success']={};e.success.collect_current(group,row['success'],first,state['provider'],h,e,e.v,state['started']);persist()
  row['success']['namespace']={};e.retirement.collect(group,row['success']['namespace'],first,row['success']['current'],row['success']['validation'],h,persist)
  e.retirement.validate_namespace(row['success']['namespace'],first,row['success']['current'],row['success']['validation'],h)
  e.success.validate(row['success'],first,state['provider'],h,e.v,state['started'])
  row['fixed']={};e.obs.sample(Path(state['appData'])/'Library/Preferences/com.dbakp.lumen.plist',h,row['fixed'],persist,[e.obs.NEW])
  row['ownedWorkspaces']=h.owned(state['appPID']);row['caseRoots']={root:os.path.lexists(root) for key in ['selection','freshSelection'] for root in state[key]['workspaces']};persist()
  row['scope']='Actual owner/root facts, not required empty: native failed before final Back. No global/live-app FD absence claim.'
  row['completedMonotonic']=time.monotonic();persist()
 result.update(status='RECORDED two later readonly process/current26/private/receipt/fixed/owner endpoints; original native FAILED0/1/0 and R8FAILED remain unchanged',scope='No app relaunch/reset/repair/sync/defaults write or host cleanup. Sampled endpoints only, no final Back/UI-success/final-closure acceptance.',finished=time.time());persist()
except BaseException:
 result.update(status='FAILED later readonly diagnostic; no acceptance',error=traceback.format_exc(),finished=time.time());persist();raise
print(json.dumps({'status':result['status'],'modes':[row['process'].get('mode') for row in result['samples']],'nativeSequences':[row.get('nativeValue',{}).get('sequence') for row in result['samples']],'ownedCounts':[len(row.get('ownedWorkspaces',{})) for row in result['samples']]}))
