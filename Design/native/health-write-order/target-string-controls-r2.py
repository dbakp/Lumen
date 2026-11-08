"""Isolated typed String observer/schema/complete-success controls. No device queries."""
from pathlib import Path
import base64,copy,gzip,hashlib,importlib.util,json,plistlib,stat,subprocess,tempfile,time,unicodedata
B=Path(__file__).resolve().parent
calls=[]
def forbidden(*args,**kwargs):calls.append(args);raise AssertionError('No process/device actions in pure controls')
original=(subprocess.run,subprocess.check_output,subprocess.Popen)
subprocess.run=subprocess.check_output=subprocess.Popen=forbidden

def module(name):
 spec=importlib.util.spec_from_file_location(name,B/(name+'.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
try:
 e=module('target-string-evidence-r2');ob=e.obs;v=e.v;h=e.h;codec=module('target-string-codec-r1');cases=[];fixtures=[]
 def case(name,accepted,body):
  try:body();actual=True
  except (AssertionError,UnicodeError,KeyError,TypeError,ValueError):actual=False
  assert actual is accepted,(name,accepted,actual)
  cases.append({'case':name,'accepted':actual})
 swift=json.loads(gzip.decompress((B/'source239-native-guard-controls-r1-fixtures.json.gz').read_bytes()));native=json.loads(swift['runStdout'])
 assert base64.b64decode(native['oldUTF16LE'])==codec.OLD and base64.b64decode(native['newUTF16LE'])==codec.NEW
 assert native['normalizationEqualInSwift'] and native['rawUnitsDiffer']
 with tempfile.TemporaryDirectory(prefix='lumen239-string-prefs-') as temp:
  path=Path(temp)/'com.dbakp.lumen.plist'
  def sample(values,allowed,bootstrap=False):
   path.write_bytes(plistlib.dumps(values));sink={};persisted=[]
   def persist():persisted.append(copy.deepcopy(sink))
   try:
    result=e.bootstrap.sample(path,h,sink,persist) if bootstrap else ob.sample(path,h,sink,persist,allowed)
    if bootstrap:v.bootstrap_fixed(sink,h)
    else:v.fixed(sink,ob.NEW if result=='new' else ob.OLD,h,ob)
    return result
   finally:fixtures.append({'kind':'bootstrap' if bootstrap else 'mutation','values':{k:repr(x) for k,x in values.items()},'allowed':[base64.b64encode(x).decode() for x in allowed],'observations':persisted})
  def values(meal=codec.OLD_TEXT,workout=codec.OLD_TEXT):return {ob.KEYS[0]:meal,ob.KEYS[1]:workout,'lumen.health.connected':False}
  case('old-string',True,lambda:sample(values(),[ob.OLD]))
  case('new-string',True,lambda:sample(values(codec.NEW_TEXT),[ob.NEW]))
  case('old-during-transition',True,lambda:sample(values(),[ob.OLD,ob.NEW]))
  for name,meal,workout in [('data-in-string-slot',codec.OLD,codec.OLD_TEXT),('normalization-equivalent',unicodedata.normalize('NFC',codec.OLD_TEXT),codec.OLD_TEXT),('wrong-workout',codec.NEW_TEXT,codec.NEW_TEXT),('unexpected-text','unexpected',codec.OLD_TEXT),('oversized-text','x'*2049,codec.OLD_TEXT),('dictionary',{},codec.OLD_TEXT),('integer',42,codec.OLD_TEXT)]:
   case(name,False,lambda meal=meal,workout=workout:sample(values(meal,workout),[ob.OLD,ob.NEW]))
  case('missing-after-mutation',False,lambda:sample({},[ob.NEW]))
  case('connected',False,lambda:sample(dict(values(),**{'lumen.health.connected':True}),[ob.OLD]))
  case('bootstrap-missing-only',True,lambda:sample({},[],True))
  case('bootstrap-old-string',True,lambda:sample(values(),[],True))
  case('bootstrap-reject-new',False,lambda:sample(values(codec.NEW_TEXT),[],True))
  case('bootstrap-reject-Data',False,lambda:sample(values(codec.OLD),[],True))
  case('bootstrap-normalization',False,lambda:sample(values(unicodedata.normalize('NFC',codec.OLD_TEXT)),[],True))
 def facts(meal):
  return {key:{name:{'present':True,'type':'Swift.String','utf16Units':len(raw)//2,'bytes':len(raw),'sha256':h.sha(raw),'payload':base64.b64encode(raw).decode()} for name in ['persisted','effective']} for key,raw in zip(ob.KEYS,[meal,ob.OLD])}
 case('native-both-string-original',True,lambda:ob.native_fixed(facts(ob.OLD),ob.OLD,h))
 case('native-new-string',True,lambda:ob.native_fixed(facts(ob.NEW),ob.NEW,h))
 def badfact(field,value):
  f=facts(ob.NEW);f[ob.KEYS[0]]['persisted'][field]=value;ob.native_fixed(f,ob.NEW,h)
 for name,field,value in [('wrong-native-type','type','Foundation.Data'),('wrong-native-digest','sha256','0'*64),('wrong-native-units','utf16Units',1),('wrong-native-payload','payload',base64.b64encode(ob.OLD).decode()),('absent-native','present',False)]:case(name,False,lambda field=field,value=value:badfact(field,value))
 host=json.loads((B/'health-legacy-target-change-data-source238r1-host-audit.json').read_bytes())
 # Source-aligned synthetic successor of retained successful Data trees; not a String runtime observation.
 first=copy.deepcopy(host['boundaries'][0]['protected']);record=copy.deepcopy(host['boundaries'][6]['success']);current=record['current']
 def write(name,raw):
  row={'bytes':len(raw),'sha256':h.sha(raw),'base64':base64.b64encode(raw).decode()};current['files'][name]=row;meta=current['metadata']['files'][name];meta['bytes']=len(raw);meta['sha256']=h.sha(raw);meta['identity']['st_size']=len(raw)
  next(r for r in current['entries'] if r['path']==name)['identity']['st_size']=len(raw)
 def jsonwrite(name,value):write(name,json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode())
 manifest_name=next(n for n,r in current['files'].items() if n.startswith('.health-recovery/') and n.endswith('/manifest.json') and json.loads(v.payload(r,h))['version']==2)
 manifest=json.loads(v.payload(current['files'][manifest_name],h));parent=str(Path(manifest_name).parent)
 for domain,raw in [('meals',ob.NEW),('workouts',ob.OLD)]:
  name=parent+'/legacy-origin-'+domain+'.json';envelope=json.loads(v.payload(current['files'][name],h));envelope.update(type='stringUTF16LE',payload=base64.b64encode(raw).decode(),sha256=h.sha(raw));jsonwrite(name,envelope);manifest['legacyOrigins'][domain]['sha256']=current['files'][name]['sha256']
 jsonwrite(manifest_name,manifest);baseline=copy.deepcopy(record)
 def valid():return e.success.validate(record,first,host['provider'],h,v,host['started'])
 case('full26-typed-string-success',True,valid)
 def broken(name,change,update_manifest=False):
  global record,current
  record=copy.deepcopy(baseline);current=record['current'];value=json.loads(v.payload(current['files'][name],h));change(value);jsonwrite(name,value)
  if update_manifest:
   m=json.loads(v.payload(current['files'][manifest_name],h));m['legacyOrigins']['meals' if 'meals' in name else 'workouts']['sha256']=current['files'][name]['sha256'];jsonwrite(manifest_name,m)
  valid()
 for label,change in [('Data-envelope',lambda x:x.update(type='data')),('stale-meals-token',lambda x:x.update(payload=base64.b64encode(ob.OLD).decode(),sha256=h.sha(ob.OLD)))]:
  case(label,False,lambda change=change:broken(parent+'/legacy-origin-meals.json',change,True))
 normalized=unicodedata.normalize('NFC',codec.OLD_TEXT).encode('utf-16-le')
 case('normalized-workout-token',False,lambda:broken(parent+'/legacy-origin-workouts.json',lambda x:x.update(payload=base64.b64encode(normalized).decode(),sha256=h.sha(normalized)),True))
 receipt=baseline['validation']['receipt']
 case('wrong-source-receipt',False,lambda:broken(receipt,lambda x:x.update(source='selected-file:'+'0'*64)))
 case('invented-photo-omission',False,lambda:broken(receipt,lambda x:x.update(omittedPhotoCount=1)))
 case('altered-existing-journal',False,lambda:broken('health-write-intent.json',lambda x:x['events'][0].update(localID='changed')))
 record=copy.deepcopy(baseline);current=record['current'];case('full26-repeat-strict',True,valid)
 # All native state gates retain structural/authority constraints with exact new typed facts.
 states=[]
 for boundary in host['boundaries']:
  value=copy.deepcopy(boundary['observation']);value['originKind']='string'
  value['bootstrapObservation']['fixed']=facts(ob.OLD)
  for index,event in enumerate(value['events']):
   if 'fixed' in event:event['fixed']=facts(ob.OLD if index<5 else ob.NEW)
  states.append(value)
  case('native-schema-'+boundary['phase'],True,lambda value=value:e.check_state(value,host['started'],host['runID'],host['appPID']))
 wrong=copy.deepcopy(states[-1]);wrong['originKind']='data';case('schema-wrong-kind',False,lambda:e.check_state(wrong,host['started']))
 wrong=copy.deepcopy(states[-1]);wrong['events'][4]['oldTokenVerified']=False;case('schema-unverified-old-token',False,lambda:e.check_state(wrong,host['started']))
 wrong=copy.deepcopy(states[-1]);wrong['events'][7]['changedClassification']=False;case('schema-forced-error-without-changed',False,lambda:e.check_state(wrong,host['started']))
 actual_host=json.loads((B/'health-legacy-target-change-string-source239r1-driver-observations.json').read_bytes())
 actual=actual_host['nativeStates'][-1];assert json.loads(base64.b64decode(actual['base64'],validate=True))==actual['value'];actual=copy.deepcopy(actual['value'])
 for label,checker in [('extended',e.check_state),('prefix',e._base.check_state),('base',e._base.parent.check_state)]:
  case('actual-shared-class-'+label,True,lambda checker=checker:checker(actual,actual_host['started'],actual_host['runID'],actual_host['appPID']))
 old_e=module('target-string-evidence-r1')
 case('original239-schema-still-rejects',False,lambda:old_e.check_state(actual,actual_host['started']))
 case('actual-shared-observer',True,lambda:ob.native_fixed(actual['events'][5]['fixed'],ob.NEW,h))
 def native_change(field,val,location='persisted',workout=False):
  changed=copy.deepcopy(actual);key=ob.KEYS[1 if workout else 0]
  changed['events'][5]['fixed'][key][location][field]=val
  e.check_state(changed,actual_host['started'])
 for label,field,val in [('Data-type-spoof','type','Foundation.Data'),('unknown-String-class','type','Unknown.String'),('shared-class-prefix-spoof','type','Swift.__SharedStringStorageExtra'),('wrong-native-hash','sha256','0'*64),('wrong-native-bytes','bytes',64),('wrong-native-units','utf16Units',32),('missing-native-value','present',False),('wrong-native-payload','payload',base64.b64encode(ob.OLD).decode())]:
  case('actual-reject-'+label,False,lambda field=field,val=val:native_change(field,val))
 case('actual-effective-Data-spoof',False,lambda:native_change('type','Foundation.Data','effective'))
 case('actual-workout-new-payload',False,lambda:native_change('payload',base64.b64encode(ob.NEW).decode(),workout=True))
 normalized_new=unicodedata.normalize('NFC',codec.NEW_TEXT).encode('utf-16-le')
 def normalized_case():
  changed=copy.deepcopy(actual);f=changed['events'][5]['fixed'][ob.KEYS[0]]['persisted'];f.update(bytes=len(normalized_new),utf16Units=len(normalized_new)//2,sha256=h.sha(normalized_new),payload=base64.b64encode(normalized_new).decode());e.check_state(changed,actual_host['started'])
 case('actual-normalized-new-payload',False,normalized_case)
 for name,edit in [('wrong-origin-kind',lambda x:x.update(originKind='data')),('old-token-unverified',lambda x:x['events'][4].update(oldTokenVerified=False)),('wrong-run-id',lambda x:x.update(runID='not-a-uuid'))]:
  def schema_edit(edit=edit):
   changed=copy.deepcopy(actual);edit(changed);e.check_state(changed,actual_host['started'])
  case('actual-'+name,False,schema_edit)
 assert not calls
 fixture={'observerFixtures':fixtures,'syntheticSuccess':baseline,'originalFirst':first,'provider':host['provider'],'nativeStateFixtures':states,'caseResults':cases,'swiftCodecOutput':native,'actual239RejectedMetadata':actual};raw=json.dumps(fixture).encode();fn='source240-string-host-controls-r1-fixtures.json.gz';(B/fn).write_bytes(gzip.compress(raw,mtime=0))
 report={'status':'PASS isolated String typed observer/bootstrap/native-schema/full26source-aligned success controls','cases':len(cases),'accepted':sum(r['accepted'] for r in cases),'rejected':sum(not r['accepted'] for r in cases),'processQueryAttempts':len(calls),'oldUTF16Bytes':len(ob.OLD),'newUTF16Bytes':len(ob.NEW),'fixture':fn,'decodedBytes':len(raw),'decodedSHA256':h.sha(raw),'scope':'Isolated temporary plists/sourcealigned synthetic full26 plus exactretained239sequence7 replay; originalR1stillrejects and originalfailedcase unchanged. No freshStringnative/runtime/permission/closure/appearance acceptance.','checkedAt':time.time()};(B/'source240-string-host-controls-r1.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
finally:subprocess.run,subprocess.check_output,subprocess.Popen=original
