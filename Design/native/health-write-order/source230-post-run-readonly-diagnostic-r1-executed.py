from pathlib import Path
import importlib.util,json,time,os,subprocess,traceback
b=Path('Design/native/health-write-order');spec=importlib.util.spec_from_file_location('postrun_evidence',b/'legacy-target-change-evidence-r2.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h
prefix='health-legacy-target-change-data-source230r1';s=h.load(b/(prefix+'-host-audit.json'));group=h.container('group.com.dbakp.lumen');app=h.container('app')/'Lumen';root=group/'LumenData';out={'scope':'Separate later readonly diagnostic after R4 FAILED final process query; not a repaired R4 outcome or native rerun','source':s['source'],'knownAppPID':s['appPID'],'executable':str(app),'samples':[]}
try:
 for ordinal in range(2):
  if ordinal:time.sleep(0.25)
  row={'at':time.time(),'monotonic':time.monotonic()};out['samples'].append(row)
  result=subprocess.run(['ps','-axo','pid=,comm='],capture_output=True,text=True,timeout=10)
  row['processQuery']={'exit':result.returncode,'stdoutBytes':len(result.stdout.encode()),'stdoutSHA256':h.sha(result.stdout.encode()),'stderr':result.stderr,'matches':[]}
  assert result.returncode==0
  for line in result.stdout.splitlines():
   parts=line.strip().split(None,1);assert len(parts)==2 and parts[0].isdigit()
   if int(parts[0])==s['appPID'] or parts[1]==str(app):row['processQuery']['matches'].append({'pid':int(parts[0]),'executable':parts[1]})
  assert not row['processQuery']['matches']
  row['protected']={};e.protected(group,row['protected'],s['boundaries'][0]['protected'])
  row['fixed']={};e.obs.sample(h.container('data')/'Library/Preferences/com.dbakp.lumen.plist',h,row['fixed'],lambda:None,[e.obs.NEW])
  row['installed']=h.installed(s['build']);row['originEvents']=e.origin_trace(group,6,s['oldSession'],s['boundaries'][5]['observation']['sessionID'])
  row['owned']=h.owned(s['appPID']);row['caseRoots']={p:os.path.lexists(p) for key in ['selection','freshSelection'] for p in s[key]['workspaces']}
  assert not row['owned'] and not any(row['caseRoots'].values())
  native=s['nativeStates'][-1];row['nativeState']={'file':native['file'],**h.row(h.read(native['file'],128*1024))};assert row['nativeState']['base64']==native['base64']
 out['status']='PASS two later sampled no-matching-app-process endpoints with full protected/newer/provider/installed/case-root preservation; R4 remains FAILED'
except BaseException:out['status']='FAILED separate post-run diagnostic';out['error']=traceback.format_exc()
finally:(b/'source230-post-run-readonly-diagnostic-r1.json').write_text(json.dumps(out,indent=2)+'\n')
print(out['status'])
