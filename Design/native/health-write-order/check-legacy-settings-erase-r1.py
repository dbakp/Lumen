"""Read-only retained/native/live verification; never reset, seed or acknowledge."""
import base64
import gzip
import importlib.util
import json
from pathlib import Path
import struct
import sys
import time
BASE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('reset_checker_evidence', BASE / 'legacy-settings-erase-evidence-r1.py')
e = importlib.util.module_from_spec(spec); spec.loader.exec_module(e)
h = e.h
prefix, output = sys.argv[1:3]
s = h.load(BASE / (prefix + '-host-audit.json')); o = h.load(BASE / (prefix + '-outcome.json'))
assert o['nativeExit'] == o['driverExit'] == 0 and o['hostError'] is None
assert not any(o.get(k) for k in ['outcomePersistenceErrors', 'finalizationPersistenceErrors', 'observationPersistenceError', 'retainerException'])
inputs = h.verify_inputs(s['source'], s['build']); h.installed(s['build'])
assert [(x['observation']['mode'],x['observation']['sequence'],x['phase']) for x in s['boundaries']] == e.PHASES
assert len(s['messages']) == 6 and all(x['status'] == 'PASS' for x in s['boundaries'])
for row in s['boundaries']:
 assert row['provider'] == s['provider']
 assert row['observation']['runID'] == s['runID']
 if row['phase'] in ['erased','relaunch','followup']:
  e.journal_reset(s['initialJournal'],row['erased']['journal']);e.journal_reset(s['initialJournal'],row['observation']['journal'])
  assert all(not x['persistedPresent'] and not x['effectivePresent'] for x in row['observation']['fixed'].values())
assert s['boundaries'][4]['observation']['pid'] != s['initialPID']
assert s['boundaries'][5]['observation']['pid'] == s['boundaries'][4]['observation']['pid']
assert s['boundaries'][5]['observation']['at'] - s['boundaries'][4]['observation']['at'] >= 3
summary = h.load(BASE / (prefix + '-summary.json'))
assert [summary[x] for x in ['passedTests','failedTests','skippedTests']] == [1,0,0]
assert summary == o['summary'] == o['retention']['summary'] and not o['retention']['errors']
images = h.load(BASE / (prefix + '-images.json')); helpers = h.load(BASE / (prefix + '-readbacks.json'))
assert len(images) == 9 and len(helpers) == 1
names = []
for row in images+helpers:
 data = h.read(BASE/row['file'],4*1024*1024)
 assert len(data)==row['bytes'] and h.sha(data)==row['sha256'] and data==h.read(row['raw'],4*1024*1024)
 if row in images:
  assert struct.unpack('>II',data[16:24])==(1206,2622)
  matches=[phase for phase in e.IMAGES if 'health-legacy-settings-erase-'+phase+'_' in row['metadata']['suggestedHumanReadableName']]
  assert len(matches)==1;names+=matches
assert sorted(names)==sorted(e.IMAGES)
helper=h.load(BASE/helpers[0]['file']);assert helper['phase']=='completed'
assert [x['phase'] for x in helper['observations'] if 'probeValue' in x]==[x[2] for x in e.PHASES]
assert '-resetForUITests' not in helper['currentLaunchArguments'] and '-health-legacy-reset-observer' in helper['currentLaunchArguments']
count=0
def payloads(value):
 global count
 if isinstance(value,dict):
  if isinstance(value.get('base64'),str) and 'bytes' in value and 'sha256' in value:
   data=base64.b64decode(value['base64'],validate=True);assert len(data)==value['bytes'] and h.sha(data)==value['sha256'];count+=1
  for child in value.values():payloads(child)
 elif isinstance(value,list):
  for child in value:payloads(child)
payloads(s)
group=h.container('group.com.dbakp.lumen');last=s['boundaries'][-1]['observation']
actual=e.erased(group,last,s['initialJournal']);assert h.provider()==s['provider'] and not h.owned(last['pid'])
assert actual['intent']['event']==s['boundaries'][3]['erased']['intent']['event']
assert actual['intent']['generation']==s['boundaries'][3]['erased']['intent']['generation']
for message in s['messages'][-1:]:assert h.load(message['file'])==message['value']
result={'status':'PASS actual Settings erase/native/retained/source/live readonly audit','source':s['source'],'case':s['case'],
 'sourceInputs':inputs['inputs'],'originals':9,'nativeHelperBytes':helpers[0]['bytes'],'embeddedPayloadsDecoded':count,
 'boundaries':6,'live':actual,'scope':'Two separately executed main/light/normal synthetic legacy types only; no universal reset interruption, speech, motion, all43 or full goal acceptance.','checkedAt':time.time()}
Path(output).write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:result[k] for k in ['status','source','case','sourceInputs','originals','nativeHelperBytes','embeddedPayloadsDecoded','boundaries']}))
