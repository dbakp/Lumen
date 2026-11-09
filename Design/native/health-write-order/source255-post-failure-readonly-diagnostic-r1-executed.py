"""Two bound-process/protected-state observations after actual failed UI run."""
from pathlib import Path
import importlib.util,json,os,time,traceback
B=Path(__file__).resolve().parent;P='health-confirmation-notnow-data-source255r1'
def module(name,file):
 s=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
e=module('failure_diagnostic_lifecycle','confirmation-lifecycle-evidence-r1.py');h=e.h
processes=module('failure_diagnostic_process','target-postrun-process-r1.py');protocol=module('failure_diagnostic_protocol','confirmation-lifecycle-protocol-r1.py')
s=h.load(B/(P+'-driver-observations.json'));first=s['boundaries'][0];group=Path(first['nativeCheckpoint']['file']).parent;window=s['confirmationWindow'];output=B/'source255-post-failure-readonly-diagnostic-r1.json';assert not output.exists()
result={'status':'Incomplete readonly failure diagnostic; no native acceptance','source':s['source'],'appPID':s['appPID'],'samples':[],'physicalPhoneActions':False,'started':time.time()}
def persist():output.write_text(json.dumps(result,indent=2)+'\n')
persist()
for index in range(2):
 if index:time.sleep(.25)
 row={'at':time.time(),'monotonic':time.monotonic(),'process':{},'errors':[]};result['samples'].append(row);persist()
 try:
  row['mode']=processes.observe(s['appPID'],first['installed']['path'],row['process'],persist)
  row['protected']={};e.protected(group,row['protected'],first['protected']);persist()
  row['fixed']={};e.obs.sample(Path(s['appData'])/'Library/Preferences/com.dbakp.lumen.plist',h,row['fixed'],persist,[h.DATA]);persist()
  row['installed']=h.installed(s['build']);assert row['installed']==first['installed']
  native=Path(s['nativeStates'][-1]['file']);raw=h.read(native,128*1024);row['native']={'file':str(native),'identity':h.identity(native),**h.row(raw)};persist()
  row['nativeValue']=json.loads(raw);e.check_state(row['nativeValue'],s['started'],s['runID'],s['appPID']);assert row['nativeValue']==s['nativeStates'][-1]['value']
  trace=Path(window['trace']['file']);raw=h.read(trace,16384);row['trace']={'file':str(trace),'identity':h.identity(trace),**h.row(raw)};persist()
  actual=json.loads(raw);protocol.trace(actual,actual['binding'],s['started'],True);assert len(actual['checks'])==1
  gate=Path(window['gate']['file']);row['ackExists']=os.path.lexists(gate.with_name(gate.stem+'-ack.json'))
  row['checkFileExists']=os.path.lexists(trace.with_suffix('.check-1.json'))
  row['uiMarkers']={phase:os.path.lexists(Path(window['runner'])/'tmp'/('Lumen-confirmation-lifecycle-ui-'+actual['binding']['nonce'].lower()+'-'+phase+'.json')) for phase in ['presented','dismissed','checked']}
  assert row['ackExists'] is True and row['checkFileExists'] and row['uiMarkers']=={'presented':True,'dismissed':True,'checked':True}
  row['acknowledgement']={'file':str(gate.with_name(gate.stem+'-ack.json')),**h.row(h.read(gate.with_name(gate.stem+'-ack.json'),4096))};persist();assert row['acknowledgement']['sha256']==window['ackBytes']['sha256']
  checkpath=trace.with_suffix('.check-1.json');checkraw=h.read(checkpath,16384);row['nativeCheck']={'file':str(checkpath),**h.row(checkraw)};persist()
  checked=json.loads(__import__('base64').b64decode(window['checked']['versions'][-1]['base64'],validate=True));ackraw=__import__('base64').b64decode(window['ackBytes']['base64'],validate=True)
  protocol.check(json.loads(checkraw),actual,ackraw,window['ackPublishedObservedAt'],checked['touchAt'],checked['tapReturnedAt'],e)
  relay=window['relays'][1];raw=h.read(relay['file'],4096);row['relay']={'file':relay['file'],**h.row(raw)};persist();assert row['relay']['sha256']==relay['raw']['sha256']
  h.source_exact(s['selection']);row['sourceExact']=True
  row['ownedWorkspaces']=h.owned(s['appPID']);row['caseRoots']={p:os.path.lexists(p) for p in s['selection']['workspaces']}
  row['originEvents']=e.origin_trace(group,1,s['oldSession']);persist()
 except BaseException:row['errors'].append(traceback.format_exc());persist()
 row['finished']=time.time();persist()
assert len(result['samples'])==2 and not any(r['errors'] for r in result['samples'])
assert result['samples'][1]['monotonic']-result['samples'][0]['monotonic']>=.25
result.update(status='Two readonly failure endpoints retained; no Back/fullcase acceptance',finished=time.time(),scope='Only sampled process identity/protected baseline/native oldData42/source/provider/trace/exactlateack and exact nativecheck. Actual nativeCheck partial evidence only. Existing source workspaces and open-ready origin trace remain; no review-owner closure/reference-release/globalFD/continuousabsence claim.');persist();print(json.dumps({'status':result['status'],'modes':[r['mode'] for r in result['samples']],'owners':[len(r.get('ownedWorkspaces',{})) for r in result['samples']]}))
