"""Isolated healthy-file protection, workout-only publication and native-schema checks."""
from pathlib import Path
import base64,copy,gzip,importlib.util,json,subprocess,time
B=Path(__file__).resolve().parent
calls=[]
def forbidden(*args,**kwargs):calls.append(args);raise AssertionError('No process/device actions in pure controls')
original=(subprocess.run,subprocess.check_output,subprocess.Popen)
subprocess.run=subprocess.check_output=subprocess.Popen=forbidden
def module(name):
 spec=importlib.util.spec_from_file_location(name,B/(name+'.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
try:
 e=module('healthy-target-evidence-r1');h=e.h;v=e.v;healthy=e.healthy;cases=[]
 def case(name,accepted,body):
  try:body();actual=True
  except (AssertionError,UnicodeError,KeyError,TypeError,ValueError):actual=False
  assert actual is accepted,(name,accepted,actual)
  cases.append({'case':name,'accepted':actual})
 host=json.loads((B/'health-legacy-target-change-data-source238r1-host-audit.json').read_bytes())
 first=copy.deepcopy(host['boundaries'][0]['protected']);baseline=copy.deepcopy(first)
 def write(tree,name,raw,identity=None):
  if identity is None:identity=copy.deepcopy(tree['metadata']['files'][name]['identity'])
  identity=copy.deepcopy(identity);identity['st_size']=len(raw)
  tree['files'][name]={'bytes':len(raw),'sha256':h.sha(raw),'base64':base64.b64encode(raw).decode()}
  tree['metadata']['files'][name]={'bytes':len(raw),'sha256':h.sha(raw),'identity':identity}
 def refresh(tree):
  directories=set()
  for name in tree['files']:
   parent=Path(name).parent
   while str(parent)!='.':directories.add(str(parent));parent=parent.parent
  old={row['path']:row['identity'] for row in tree['entries'] if row['kind']=='directory'}
  tree['metadata']['directories']=sorted(directories)
  tree['entries']=[{'path':name,'kind':'regular','identity':copy.deepcopy(row['identity'])} for name,row in tree['metadata']['files'].items()]
  tree['entries'] += [{'path':name,'kind':'directory','identity':copy.deepcopy(old[name])} for name in sorted(directories)]
 identity=copy.deepcopy(first['current']['metadata']['files']['health-write-intent.json']['identity']);identity['st_ino']+=987654
 write(baseline['current'],'meals.json',healthy.HEALTHY,identity);refresh(baseline['current'])
 root='/synthetic/LumenData'
 leaf={'path':root+'/meals.json','exists':True,'errno':0,'identity':copy.deepcopy(baseline['current']['metadata']['files']['meals.json']['identity']),'bytes':len(healthy.HEALTHY),'sha256':h.sha(healthy.HEALTHY),'payload':base64.b64encode(healthy.HEALTHY).decode()}
 missing={'path':leaf['path'],'exists':False,'errno':2}
 def protected(row=baseline,native=leaf):return healthy.validate(row,first,native,h,v)
 case('healthy14-preserves-all13-and-prior13',True,protected)
 case('known-missing-before-write',True,lambda:healthy.native_leaf(missing,root,False,h))
 for label,edit in [('wrong-path',lambda x:x.update(path='/other/meals.json')),('wrong-payload',lambda x:x.update(payload=base64.b64encode(b'[]').decode())),('wrong-hash',lambda x:x.update(sha256='0'*64)),('bool-size',lambda x:x.update(bytes=True)),('symlink',lambda x:x['identity'].update(st_mode=41471)),('unknown-field',lambda x:x.update(extra=True))]:
  def check(edit=edit):
   row=copy.deepcopy(leaf);edit(row);healthy.native_leaf(row,root,True,h)
  case('native-reject-'+label,False,check)
 for label,edit in [('changed-old-inode',lambda x:x['current']['metadata']['files']['health-write-intent.json']['identity'].update(st_ino=1)),('changed-prior',lambda x:x['prior']['rootIdentity'].update(st_ino=1)),('changed-provider',lambda x:x['provider'].update(sha256='0'*64)),('extra-stage',lambda x:x['residuals']['LumenData.restore-*'].append('/synthetic/stage')),('wrong-current-root',lambda x:x['current']['rootIdentity'].update(st_ino=1)),('missing-healthy-leaf',lambda x:x['current']['files'].pop('meals.json'))]:
  def check(edit=edit):
   row=copy.deepcopy(baseline);edit(row);protected(row)
  case('protected-reject-'+label,False,check)
 record=copy.deepcopy(host['boundaries'][6]['success']);current=record['current']
 def jsonwrite(name,value):write(current,name,json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode())
 write(current,'meals.json',healthy.HEALTHY,baseline['current']['metadata']['files']['meals.json']['identity'])
 for name in list(current['files']):
  if name.startswith('photos/'):
   del current['files'][name];del current['metadata']['files'][name]
 manifests=[name for name in current['files'] if name.startswith('.health-recovery/') and name.endswith('/manifest.json') and name not in first['current']['files']]
 for name in manifests:
  value=json.loads(v.payload(current['files'][name],h));value['domains']=['workouts'];parent=str(Path(name).parent)
  removed=parent+('/legacy-origin-meals.json' if value['version']==2 else '/meals.json')
  del current['files'][removed];del current['metadata']['files'][removed]
  if value['version']==2:
   del value['legacyOrigins']['meals']
   workout=parent+'/legacy-origin-workouts.json';envelope=json.loads(v.payload(current['files'][workout],h))
   assert base64.b64decode(envelope['payload'])==h.DATA
  jsonwrite(name,value)
 receipt=record['validation']['receipt'];value=json.loads(v.payload(current['files'][receipt],h))
 value.update(domains=['workouts'],recordDigests={'workouts.json':current['files']['workouts.json']['sha256']},photoDigests={},reviewedPhotos={},omittedPhotoCount=0);jsonwrite(receipt,value)
 refresh(current);record.pop('validation',None)
 valid_record=copy.deepcopy(record)
 def success():return e.success.validate(record,baseline,host['provider'],h,v,host['started'])
 case('full22-workout-only-healthy-preserved',True,success)
 validation=success();retired=e.retirement.expected(baseline,current,validation)
 case('retired14-plus-selected-prior3-equals17',True,lambda: (_ for _ in ()).throw(AssertionError()) if len(retired[0])!=17 else None)
 for label,name,edit in [('wrong-receipt-domain',receipt,lambda x:x.update(domains=['meals','workouts'])),('invented-omission',receipt,lambda x:x.update(omittedPhotoCount=1)),('changed-journal','health-write-intent.json',lambda x:x['events'][0].update(localID='changed'))]:
  def check(name=name,edit=edit):
   global record,current
   record=copy.deepcopy(valid_record);current=record['current'];value=json.loads(v.payload(current['files'][name],h));edit(value);jsonwrite(name,value);refresh(current);success()
  case('success-reject-'+label,False,check)
 record=copy.deepcopy(valid_record);current=record['current']
 def overwritten():
  write(current,'meals.json',b'[]');refresh(current);success()
 case('success-reject-overwritten-healthy-meal',False,overwritten)
 record=copy.deepcopy(valid_record);current=record['current'];case('full22-repeat-strict',True,success)
 states=[]
 for boundary in host['boundaries']:
  value=copy.deepcopy(boundary['observation']);value.update(verificationProtocol=e.PROTOCOL,originKind='data',targetKind='healthy-current-file',knownFileWritten=value.pop('knownKeyWritten'))
  for index,event in enumerate(value['events']):
   if index in [3,4,5,6]:
    event['mealFile']=copy.deepcopy(missing if index<5 else leaf)
    event['fixed']=copy.deepcopy(value['events'][3]['fixed'])
   if index==11:event['domains']=['workouts']
  states.append(value)
  case('native-schema-'+boundary['phase'],True,lambda value=value:e.check_state(value,host['started'],host['runID'],host['appPID']))
 for label,edit in [('wrong-kind',lambda x:x.update(targetKind='preferences')),('unverified-token',lambda x:x['events'][4].update(oldTokenVerified=False)),('fresh-healthy-meal-offered',lambda x:x['events'][11].update(domains=['meals','workouts'])),('wrong-fixed-origin',lambda x:x['events'][5]['fixed'][e.obs.KEYS[0]]['persisted'].update(payload=base64.b64encode(e.obs.NEW).decode()))]:
  def check(edit=edit):
   value=copy.deepcopy(states[-1]);edit(value);e.check_state(value,host['started'])
  case('schema-reject-'+label,False,check)
 assert not calls
 fixture={'first13':first,'healthy14':baseline,'nativeHealthyLeaf':leaf,'syntheticSuccess22':valid_record,'nativeStates':states,'cases':cases}
 raw=json.dumps(fixture).encode();fn='source241-healthy-host-controls-r1-fixtures.json.gz';(B/fn).write_bytes(gzip.compress(raw,mtime=0))
 report={'status':'PASS isolated healthy-file/workout-only/native-schema controls','cases':len(cases),'accepted':sum(x['accepted'] for x in cases),'rejected':sum(not x['accepted'] for x in cases),'processQueryAttempts':len(calls),'healthyBytes':len(healthy.HEALTHY),'healthyBaselineFiles':14,'successFiles':22,'retirementExpectedFiles':17,'fixture':fn,'decodedBytes':len(raw),'decodedSHA256':h.sha(raw),'scope':'Synthetic source-aligned transformations of retained238 records; no new healthy-target native execution or product acceptance.','checkedAt':time.time()}
 (B/'source241-healthy-host-controls-r1.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
finally:subprocess.run,subprocess.check_output,subprocess.Popen=original
