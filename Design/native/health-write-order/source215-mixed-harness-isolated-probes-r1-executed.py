"""Isolated failure-path probes; no app/simulator/default-domain operations."""
import base64,gzip,hashlib,importlib.util,json,plistlib,shutil,subprocess,time
from pathlib import Path
repo=Path('/Users/davidbakposada/Documents/ChatGPT/Lumen');base=repo/'Design/native/health-write-order'
work=Path('/tmp/LumenMixedHarnessProbe215R1');assert not work.exists();work.mkdir()
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,base/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
retainer=module('retainer','retain-mixed-ineligible-results-r1.py');h=module('helper','health-mixed-ineligible-evidence-r1.py')
manifest=json.loads((base/'durable-source-r215.json').read_text());sha=lambda data:hashlib.sha256(data).hexdigest()
for name,row in manifest['files'].items():
 data=(repo/name).read_bytes();assert len(data)==row['bytes'] and sha(data)==row['sha256']
raw=work/'raw';dest=work/'retained';raw.mkdir();dest.mkdir();stem='IsolatedProbe';prefix='isolated-probe';(raw/(stem+'.log')).write_bytes(b'Actual isolated synthetic host probe log\n')
(raw/(stem+'.xcresult')).mkdir();(raw/(stem+'.xcresult')/'synthetic-partial.bin').write_bytes(b'synthetic partial inventory')
original_run=retainer.subprocess.run
original_write=Path.write_text;index_failures=[]
def one_index_failure(path,data,*args,**kwargs):
 if path==dest/(prefix+'-images.json') and not index_failures:
  index_failures.append(str(path));raise PermissionError('Synthetic one-index write failure')
 return original_write(path,data,*args,**kwargs)
calls=[]
def fake_run(command,capture_output):
 calls.append(command)
 if 'summary' in command:return subprocess.CompletedProcess(command,65,b'',b'Synthetic summary unavailable')
 ext='PNG' if command[-1]=='*.png' else 'JSON';folder=raw/(stem+ext);folder.mkdir()
 data=b'synthetic exact retained PNG peer' if ext=='PNG' else b'{"synthetic":"complete native helper peer"}'
 name='known-peer.'+('png' if ext=='PNG' else 'json');(folder/name).write_bytes(data)
 rows=[{}, {'testIdentifier':'isolated-host-probe','attachments':[{'exportedFileName':'missing-peer.bin','suggestedHumanReadableName':'known missing fixture'},
   {'exportedFileName':name,'suggestedHumanReadableName':'available exact peer'}]}]
 (folder/'manifest.json').write_text(json.dumps(rows)+'\n')
 return subprocess.CompletedProcess(command,65 if ext=='PNG' else 0,b'partial export',b'synthetic export fault' if ext=='PNG' else b'')
try:
 retainer.subprocess.run=fake_run;Path.write_text=one_index_failure
 retained=retainer.retain(dest,raw,stem,prefix,'durable-source-r215.json')
finally:retainer.subprocess.run=original_run;Path.write_text=original_write
assert retained['summary'] is None and retained['summaryAvailable'] is False
assert len(retained['images'])==len(retained['readbacks'])==1 and len(retained['errors'])==7 and len(index_failures)==1
for ext,index in [('PNG','images'),('JSON','readbacks')]:
 row=retained[index][0];assert (dest/row['file']).read_bytes()==Path(row['raw']).read_bytes()
 manifestrow=retained[index+'Manifest'];assert gzip.decompress((dest/manifestrow['retained']).read_bytes())==(raw/(stem+ext)/'manifest.json').read_bytes()
assert (dest/(prefix+'-retention-state.json')).exists() and (dest/(prefix+'-images.json')).exists()
assert len(retained['bundleInventory'])==1 and retained['bundleInventory'][0]['path']=='synthetic-partial.bin'
# Verify exact wrong supported bytes are already attached when validation throws.
container=work/'synthetic-container';prefs=container/'Library/Preferences';prefs.mkdir(parents=True)
expected={'bundle':'com.dbakp.lumen','kind':'mixed-data','values':{'meals':{'key':'lumen.health.meals.v1','type':'propertyListDictionary','payload':base64.b64encode(json.dumps(h.DICTIONARY,sort_keys=True,separators=(',',':')).encode()).decode()},'workouts':{'key':'lumen.health.workouts.v1','type':'data','payload':base64.b64encode(h.DATA).decode()}}}
original_container=h.container;h.container=lambda kind:container
wrong=b'Synthetic wrong workouts bytes'
try:
 (prefs/'com.dbakp.lumen.plist').write_bytes(plistlib.dumps({'lumen.health.meals.v1':h.DICTIONARY,'lumen.health.workouts.v1':wrong}))
 observed={}
 try:h.fixed(expected,observed);raise RuntimeError('Wrong bytes should have failed')
 except AssertionError:pass
 assert observed['workouts']['base64']==base64.b64encode(wrong).decode() and observed['workouts']['sha256']==sha(wrong)
 wrong_meals={'synthetic':'Synthetic changed unsupported saved meals'}
 (prefs/'com.dbakp.lumen.plist').write_bytes(plistlib.dumps({'lumen.health.meals.v1':wrong_meals,'lumen.health.workouts.v1':h.DATA}))
 observed_meals={}
 try:h.fixed(expected,observed_meals);raise RuntimeError('Wrong dictionary should have failed')
 except AssertionError:pass
 assert observed_meals['meals']['value']==wrong_meals and base64.b64decode(observed_meals['meals']['base64'])==json.dumps(wrong_meals,sort_keys=True,separators=(',',':')).encode()
finally:h.container=original_container
# Empty unknown directories are visible and rejected by the derived allowed list.
tree=work/'tree';tree.mkdir();(tree/'known').write_bytes(b'known');before_dirs=h.directories(tree);(tree/'orphan-empty').mkdir()
assert h.directories(tree)!=h.allowed_directories(before_dirs,h.snapshot(tree))
try:h.directories(work/'vanished-known-retirement-root');raise RuntimeError('Missing known root should be ENOENT')
except FileNotFoundError:pass
report={'status':'PASS isolated host failure-path probes only','source':'durable-source-r215.json','sourceSHA256':sha((base/'durable-source-r215.json').read_bytes()),'executedProbeSHA256':sha(Path(__file__).read_bytes()),'checks':['Failed summary/PNGexport do not suppress exact available PNG/JSON peers','Malformed first case and missing entry do not suppress next available peer','One PNG index-write failure does not suppress later JSON or final indexes','Both original manifest bytes retained exactly','Actual partial bundle inventory retained','Wrong Data exact bytes/type/hash present before assertion','Wrong known dictionary diagnostic/value/hash present before assertion','Unknown empty directory visible and differs from exact allowed directory list','Missing directory inventory root preserves FileNotFound classification for bounded retirement observer'],'nativeExecution':False,'simulatorOperations':False,'expectedSyntheticRetentionErrors':retained['errors'],'actualWrongData':observed['workouts'],'actualWrongDictionary':observed_meals['meals'],'retainedPeerHashes':[{k:r[k] for k in ['file','bytes','sha256']} for r in retained['images']+retained['readbacks']],'checkedAt':time.time(),'availableBytes':shutil.disk_usage(repo).free,'rawProbeWork':str(work)}
(base/'source215-mixed-harness-isolated-probes-r1.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'status':report['status'],'checks':len(report['checks']),'nativeExecution':False}),flush=True)
