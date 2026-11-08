"""Readonly current preflight diagnostic/native/source/unchanged-data verification."""
import base64,json,importlib.util,struct,sys,time
from pathlib import Path
BASE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('preflight_diagnostic_checker',BASE/'reset-preflight-diagnostic-evidence-r1.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h
prefix,output=sys.argv[1:3];s=h.load(BASE/(prefix+'-host-audit.json'));o=h.load(BASE/(prefix+'-outcome.json'))
assert o['nativeExit']==o['driverExit']==0 and o['hostError'] is None
assert not (BASE/(prefix+'-outcome.json.emergency.json')).exists()
assert not any(o.get(k) for k in ['outcomePersistenceErrors','finalizationPersistenceErrors','nativeFinalizationError','retainerException','salvageException','emergencyOutcomePersistenceError'])
inputs=h.verify_inputs(s['source'],s['build']);h.installed(s['build']);classification=e.validate(s['diagnostic'],s['started'])
assert s['classification']==classification and s['unchangedAtDiagnostic'] is True
e.unchanged(s['before'],s['after']);e.unchanged(s['before'],s['afterNative'])
group=h.container('group.com.dbakp.lumen');actual={};e.snapshot(group,actual,s['legacy']);e.unchanged(s['before'],actual)
data=h.read(s['rawDiagnostic']['file']);assert h.row(data)=={k:s['rawDiagnostic'][k] for k in ['bytes','sha256','base64']}
assert json.loads(data)==s['diagnostic'] and not h.owned(s['diagnostic']['pid'])
summary=h.load(BASE/(prefix+'-summary.json'));assert summary==o['summary']==o['retention']['summary']
assert [summary[k] for k in ['passedTests','failedTests','skippedTests']]==[1,0,0] and not o['retention']['errors']
images=h.load(BASE/(prefix+'-images.json'));helpers=h.load(BASE/(prefix+'-readbacks.json'));assert len(images)==len(helpers)==1
for row in images+helpers:
 data=h.read(BASE/row['file'],4*1024*1024);assert len(data)==row['bytes'] and h.sha(data)==row['sha256'] and data==h.read(row['raw'],4*1024*1024)
 if row in images:assert struct.unpack('>II',data[16:24])==(1206,2622)
helper=h.load(BASE/helpers[0]['file']);assert helper['statusValue']==classification and helper['settingsEraseAttempted'] is False
assert '-health-legacy-reset-diagnostic-only' in helper['launchArguments']
count=0
def payloads(value):
 global count
 if isinstance(value,dict):
  if isinstance(value.get('base64'),str) and 'bytes' in value and 'sha256' in value:
   d=base64.b64decode(value['base64'],validate=True);assert len(d)==value['bytes'] and h.sha(d)==value['sha256'];count+=1
  for child in value.values():payloads(child)
 elif isinstance(value,list):
  for child in value:payloads(child)
payloads(s)
result={'status':'PASS read-only metadata-only preflight diagnostic; actual Settings erase unexecuted','source':s['source'],'sourceInputs':inputs['inputs'],
 'classification':classification,'nativeCounts':[1,0,0],'originals':1,'fullHelperBytes':helpers[0]['bytes'],'payloadsDecoded':count,
 'currentPriorFixedProviderUnchanged':True,'scope':'Actual diagnostic UI/native/source/data endpoints only. No credential values, generic reset, Settings erase/no-resurrection/fullgoal acceptance.','checkedAt':time.time()}
Path(output).write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
