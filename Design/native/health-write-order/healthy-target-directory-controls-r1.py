"""Pure replay of actual failed directory-entry observation and strict negatives."""
from pathlib import Path
import base64,copy,gzip,importlib.util,json,subprocess,time
B=Path(__file__).resolve().parent;calls=[]
def forbidden(*args,**kwargs):calls.append(args);raise AssertionError('No process/device action in isolated directory controls')
original=(subprocess.run,subprocess.check_output,subprocess.Popen);subprocess.run=subprocess.check_output=subprocess.Popen=forbidden
def module(name):
 spec=importlib.util.spec_from_file_location(name,B/(name+'.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
try:
 e=module('healthy-target-evidence-r3');old=module('healthy-target-protected-r1');h=e.h;v=e.v;cases=[]
 state=json.loads((B/'health-healthy-target-change-data-source242r1-driver-observations.json').read_bytes());first=state['boundaries'][0]['protected'];actual=state['boundaries'][2]['protected'];leaf=state['nativeStates'][-1]['value']['events'][6]['mealFile']
 def case(name,accepted,body):
  try:body();accepted_actual=True
  except (AssertionError,KeyError,TypeError,ValueError):accepted_actual=False
  assert accepted_actual is accepted,(name,accepted,accepted_actual)
  cases.append({'case':name,'accepted':accepted_actual})
 def validate(row=actual,native=leaf,reference=None):return e.healthy.validate(row,first,native,h,v,reference)
 case('actual242-one-added-known-leaf-link-plus1',True,validate)
 case('actual242-exact-healthybaseline-repeat',True,lambda:validate(reference=actual))
 case('original241242-predicate-still-rejects-actual',False,lambda:old.validate(actual,first,leaf,h,v))
 for name,layer in [('extended',e),('prefix',e._base),('base',e._base.parent)]:
  case('actual242-protected-'+name,True,lambda layer=layer:layer.healthy.validate(actual,first,leaf,h,v))
  for n,record in enumerate(state['nativeStates']):
   case('actual242-native-'+name+'-'+str(n),True,lambda layer=layer,record=record:layer.check_state(record['value'],state['started'],state['runID'],state['appPID']))
 def edit_row(edit,reference=None):
  row=copy.deepcopy(actual);edit(row);return validate(row,reference=reference)
 for label,edit in [
  ('nlink-plus2',lambda x:x['current']['rootIdentity'].update(st_nlink=first['current']['rootIdentity']['st_nlink']+2)),
  ('nlink-decrease',lambda x:x['current']['rootIdentity'].update(st_nlink=first['current']['rootIdentity']['st_nlink']-1)),
  ('nlink-bool',lambda x:x['current']['rootIdentity'].update(st_nlink=True)),
  ('nlink-float',lambda x:x['current']['rootIdentity'].update(st_nlink=14.0)),
  ('root-inode',lambda x:x['current']['rootIdentity'].update(st_ino=1)),
  ('root-device',lambda x:x['current']['rootIdentity'].update(st_dev=1)),
  ('root-mode',lambda x:x['current']['rootIdentity'].update(st_mode=16877)),
  ('old-inode',lambda x:x['current']['metadata']['files']['health-write-intent.json']['identity'].update(st_ino=1)),
  ('old-bytes',lambda x:x['current']['files']['health-write-intent.json'].update(base64=base64.b64encode(b'{}').decode())),
  ('prior-root',lambda x:x['prior']['rootIdentity'].update(st_ino=1)),
  ('provider',lambda x:x['provider'].update(sha256='0'*64)),
  ('extra-directory',lambda x:x['current']['metadata']['directories'].append('unexpected')),
  ('missing-healthy',lambda x:x['current']['files'].pop('meals.json')),
  ('extra-current',lambda x:x['current']['files'].update({'unexpected.json':copy.deepcopy(x['current']['files']['meals.json'])})),
  ('stage-root',lambda x:x['residuals']['LumenData.restore-*'].append('/synthetic/unknown'))]:
  case('reject-'+label,False,lambda edit=edit:edit_row(edit))
 case('bounded-unchanged-link-filesystem-shape',True,lambda:edit_row(lambda x:x['current']['rootIdentity'].update(st_nlink=first['current']['rootIdentity']['st_nlink'])))
 case('later-reference-rejects-link-change',False,lambda:edit_row(lambda x:x['current']['rootIdentity'].update(st_nlink=first['current']['rootIdentity']['st_nlink']),actual))
 for name,key,value in [('native-inode','identity',dict(leaf['identity'],st_ino=1)),('native-path','path','/synthetic/wrong/meals.json'),('native-payload','payload',base64.b64encode(b'[]').decode()),('native-digest','sha256','0'*64)]:
  def check(key=key,value=value):
   native=copy.deepcopy(leaf);native[key]=value
   if key=='path':e.healthy.native_leaf(native,Path(leaf['path']).parent,True,h)
   else:validate(native=native)
  case('reject-'+name,False,check)
 # Preserve full source-aligned workout-only22 and selected-prior retirement17.
 prior=json.loads(gzip.decompress((B/'source241-healthy-host-controls-r1-fixtures.json.gz').read_bytes()));baseline=prior['healthy14'];success=prior['syntheticSuccess22'];provider=baseline['provider'];started=state['started']
 # The retained synthetic receipt timestamp belongs to its original238 producer.
 original_case=json.loads((B/'health-legacy-target-change-data-source238r1-host-audit.json').read_bytes())
 proof=e.success.validate(success,baseline,provider,h,v,original_case['started'])
 case('sourcealigned-full22-workout-only-carry',True,lambda:e.success.validate(success,baseline,provider,h,v,original_case['started']))
 case('sourcealigned-retirement17-carry',True,lambda:len(e.retirement.expected(baseline,success['current'],proof)[0])==17 or (_ for _ in ()).throw(AssertionError()))
 assert not calls
 fixture={'actualFirst13':first,'actualChanged14':actual,'actualNativeLeaf':leaf,'actualNativeStates':[n['value'] for n in state['nativeStates']],'sourceAlignedSuccess22':success,'caseResults':cases};raw=json.dumps(fixture).encode();fn='source243-directory-controls-r1-fixtures.json.gz';assert not (B/fn).exists();(B/fn).write_bytes(gzip.compress(raw,mtime=0))
 report={'status':'PASS actual242retained rootdelta replay and strictnegatives; originalpredicate remains rejected','cases':len(cases),'accepted':sum(x['accepted'] for x in cases),'rejected':sum(not x['accepted'] for x in cases),'processQueryAttempts':len(calls),'fixture':fn,'decodedBytes':len(raw),'decodedSHA256':h.sha(raw),'scope':'Retainedactual242observations and unchangedsourcealignedsynthetic22/17; no freshnative/recovery/eligibility/closure acceptance. All674compiled242inputs unchanged.','checkedAt':time.time()};(B/'source243-directory-controls-r1.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
finally:subprocess.run,subprocess.check_output,subprocess.Popen=original
