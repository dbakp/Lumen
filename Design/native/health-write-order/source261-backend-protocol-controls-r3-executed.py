"""Pure endpoint predicates over actual synthetic OS transaction samples + tampered candidates."""
from pathlib import Path
import base64,copy,datetime,gzip,hashlib,importlib.util,json,os,plistlib,shutil,tempfile,time,uuid
B=Path(__file__).resolve().parent;output=B/'source261-backend-protocol-controls-r3.json';rawout=B/'source261-backend-protocol-controls-r3-raw.json.gz';assert not output.exists() and not rawout.exists()
def module(name):
 spec=importlib.util.spec_from_file_location(name,B/name);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
p=module('retained-backend-protocol-r3.py');s=module('retained-backend-snapshot-r2.py')
source_before=(B/'retained-backend-protocol-r3.py').read_bytes();history_name='source260-children-poststate-raw-r1.json.gz';history=json.loads(gzip.decompress((B/history_name).read_bytes()))
prior=history['files'];old_prefix=next(n[:-len('meals.json')] for n in prior if n.startswith('.health-recovery/discovered-') and n.endswith('/meals.json'))
identifier=old_prefix.split('/')[1];copy_id='healthRecoveryCopy-'+identifier
old_private=next(n[:-len('meals.json')] for n in prior if n.startswith('.health-recovery/') and not n.startswith(old_prefix) and n.endswith('/meals.json'))
def data(name):return base64.b64decode(prior[name]['base64'],validate=True)
def iso():return datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
def write(path,value):
 path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(value)
def encoded(value):return json.dumps(value,sort_keys=True,separators=(',',':')).encode()
def atomic(path,value):
 temporary=path.with_suffix(path.suffix+'.synthetic');temporary.write_bytes(value);os.replace(temporary,path)
checks=[]
with tempfile.TemporaryDirectory(prefix='lumen261-protocol-') as temporary:
 area=Path(temporary).resolve();current=area/'current';previous=area/'previous';std=area/'standardPreferences';shared_dir=area/'groupPreferences'
 for folder in [current,previous,std,shared_dir]:folder.mkdir()
 for name in p.BASE:
  original=data(old_prefix+name) if name.endswith('.json') and name.split('.')[0] in p.DOMAINS else data(name) if name in prior else data(old_prefix+'photos/synthetic-review-photo.jpg')
  if name=='health-write-intent.json':original=data(old_private+'device-intent.json')
  write(previous/name,original)
  write(current/name,p.FAILED.get(name,original))
 for name in p.OPTIONAL:write(current/name,data(name))
 for name in {d+'.json' for d in p.DOMAINS}|{'device-intent.json','photos/synthetic-review-photo.jpg','manifest.json'}:
  target=current/old_prefix/name;target.parent.mkdir(parents=True,exist_ok=True)
  if name=='manifest.json':target.write_bytes(data(old_prefix+name))
  else:os.link(previous/('health-write-intent.json' if name=='device-intent.json' else name),target)
 standard={'lumen.health.connected':False,'unchanged.standard':bytes([0,255])}
 timestamp=time.time()-978307200
 packet={'day':timestamp,'capturedAt':timestamp,'values':{},'estimates':[]}
 shared={'health.localStorageIssue':p.issue(p.DOMAINS),'widget.evidence.v1':encoded(packet),'widget.eaten':0,'widget.protein':0,'unchanged.shared':bytes([255,0])}
 write(std/'com.dbakp.lumen.plist',plistlib.dumps(standard,fmt=plistlib.FMT_BINARY))
 write(shared_dir/'group.com.dbakp.lumen.plist',plistlib.dumps(shared,fmt=plistlib.FMT_BINARY))
 roots={'current':current,'previous':previous,'standardPreferences':std,'groupPreferences':shared_dir}
 before=s.capture(roots);p.validate_pre(before,copy_id)
 stage=area/'stage';shutil.copytree(current,stage,copy_function=os.link)
 incident=str(uuid.uuid4()).upper();private=stage/'.health-recovery'/incident;private.mkdir(mode=0o700)
 os.rename(stage/'meals.json',private/'meals.json');os.rename(stage/'photos',private/'photos');os.link(stage/'health-write-intent.json',private/'device-intent.json')
 write(private/'manifest.json',encoded({'version':1,'createdAt':iso(),'domains':['meals'],'photos':True,'intent':True}))
 new_photo=str(uuid.uuid4()).upper();source_meals=json.loads(data(old_prefix+'meals.json'))
 new_meals=encoded([dict(m,photoID=new_photo) for m in source_meals]);atomic(stage/'meals.json',new_meals)
 initial=json.loads(data(old_private+'device-intent.json'));new_journal=dict(initial,lifecycle=str(uuid.uuid4()).upper());atomic(stage/'health-write-intent.json',encoded(new_journal))
 photo_path='photos/'+new_photo+'.jpg';photo=data(old_prefix+'photos/synthetic-review-photo.jpg');write(stage/photo_path,photo)
 receipt_path='.health-recovery-history/'+str(uuid.uuid4()).upper()+'.json';write(stage/receipt_path,encoded({'source':'retained:'+identifier,'domains':['meals'],'recordDigests':{'meals.json':hashlib.sha256(new_meals).hexdigest()},'photoDigests':{photo_path:hashlib.sha256(photo).hexdigest()},'recoveredAt':iso()}))
 os.rename(current,area/'retired');os.rename(stage,current);shutil.rmtree(area/'retired');shutil.rmtree(previous)
 shared['health.localStorageIssue']=p.issue(p.DOMAINS-{'meals'})
 timestamp=time.time()-978307200;shared['widget.evidence.v1']=encoded({'day':timestamp,'capturedAt':timestamp,'values':{},'estimates':[]})
 atomic(shared_dir/'group.com.dbakp.lumen.plist',plistlib.dumps(shared,fmt=plistlib.FMT_BINARY))
 after=s.capture(roots);outcome=p.validate_post(before,after,copy_id);terminal=s.capture(roots);p.validate_post(before,terminal,copy_id,after)
 checks.append({'case':'actual synthetic full pre/post/terminal files and intended transitions','accepted':True,'outcome':outcome})
 def row(value,label,path):
  found=value['roots'][label]
  for part in path.split('/'):found=found['children'][part]
  return found
 def replace(value,label,path,new):
  target=row(value,label,path);delta=len(new)-target['raw']['bytes'];target['raw']=s.raw_fact(new);value['totalReadBytes']+=delta
  for key in ['identityObserved','identityBefore','identityAfter','identityNamedAfter']:target[key]['st_size']=len(new)
 def reject(label,change):
  a=copy.deepcopy(before);b=copy.deepcopy(after);change(a,b)
  try:p.validate_post(a,b,copy_id)
  except (AssertionError,KeyError,ValueError,TypeError):checks.append({'case':label,'accepted':False});return
  raise AssertionError(label+' accepted unexpectedly')
 reject('changed unselected raw water',lambda a,b:replace(b,'current','water.json',b'changed'))
 reject('changed permanent source photo',lambda a,b:replace(b,'current',old_prefix+'photos/synthetic-review-photo.jpg',b'changed'))
 def receipt_change(a,b,field,value):
  r=json.loads(p.raw(row(b,'current',receipt_path)));r[field]=value;replace(b,'current',receipt_path,encoded(r))
 reject('receipt expands selected domains',lambda a,b:receipt_change(a,b,'domains',['meals','water']))
 reject('receipt wrong actual retained source',lambda a,b:receipt_change(a,b,'source','retained:wrong'))
 def meal_change(a,b):
  meals=json.loads(p.raw(row(b,'current','meals.json')));meals[0]['items'][0]['calories']=191;raw=encoded(meals);replace(b,'current','meals.json',raw);receipt_change(a,b,'recordDigests',{'meals.json':hashlib.sha256(raw).hexdigest()})
 reject('changed nested meal despite coherent digest',meal_change)
 def photo_change(a,b):
  replace(b,'current',photo_path,b'changed');receipt_change(a,b,'photoDigests',{photo_path:hashlib.sha256(b'changed').hexdigest()})
 reject('changed recovered photo despite coherent digest',photo_change)
 reject('private failed original changed',lambda a,b:replace(b,'current','.health-recovery/'+incident+'/meals.json',b'changed'))
 def identity_change(a,b):
  target=row(b,'current','.health-recovery/'+incident+'/meals.json')
  for key in ['identityObserved','identityBefore','identityAfter','identityNamedAfter']:target[key]['st_ino']+=1
 reject('private original inode changed with exact raw bytes',identity_change)
 for field,value in [('owner',str(uuid.uuid4()).upper()),('lifecycle',initial['lifecycle']),('version',True),('events',[{'unexpected':'event'}])]:
  def changed(a,b,field=field,value=value):
   journal=json.loads(p.raw(row(b,'current','health-write-intent.json')));journal[field]=value;replace(b,'current','health-write-intent.json',encoded(journal))
  reject('journal invalid '+field,changed)
 reject('Boolean one-byte count alias',lambda a,b:row(b,'current','.health-recovery/'+incident+'/meals.json')['raw'].update(bytes=True))
 reject('floating entry count alias',lambda a,b:b.update(entries=float(b['entries'])))
 def standard_change(a,b):
  value=plistlib.loads(p.raw(row(b,'standardPreferences','com.dbakp.lumen.plist')));value['lumen.health.meals.v1']=b'[]';replace(b,'standardPreferences','com.dbakp.lumen.plist',plistlib.dumps(value,fmt=plistlib.FMT_BINARY))
 reject('new persisted legacy default',standard_change)
 def shared_change(a,b):
  value=plistlib.loads(p.raw(row(b,'groupPreferences','group.com.dbakp.lumen.plist')));value['unchanged.shared']=b'changed';replace(b,'groupPreferences','group.com.dbakp.lumen.plist',plistlib.dumps(value,fmt=plistlib.FMT_BINARY))
 reject('unrelated shared default changed',shared_change)
 def food_change(a,b):
  value=plistlib.loads(p.raw(row(b,'groupPreferences','group.com.dbakp.lumen.plist')));packet=json.loads(value['widget.evidence.v1']);packet['values']['calories']=0;value['widget.evidence.v1']=encoded(packet);replace(b,'groupPreferences','group.com.dbakp.lumen.plist',plistlib.dumps(value,fmt=plistlib.FMT_BINARY))
 reject('invents current-day nutrition zero from old meals',food_change)
 def bad_absence(a,b):b['roots']['previous']={'path':b['roots']['previous']['path'],'absent':True,'absentParentObserved':True}
 reject('unanchored ancestor absence masquerading as leaf',bad_absence)
 def contradictory_meals_alias(a,b):
  target=row(b,'current','meals.json');original=row(b,'current','.health-recovery/'+incident+'/meals.json')
  for key in ['identityObserved','identityBefore','identityAfter','identityNamedAfter']:
   target[key]['st_dev']=original[key]['st_dev'];target[key]['st_ino']=original[key]['st_ino']
 reject('cross-row same inode contradicts one-byte private original',contradictory_meals_alias)
 def coherent_photo_alias(a,b):
  target=row(b,'current',photo_path);original=row(b,'current',old_prefix+'photos/synthetic-review-photo.jpg')
  for key in ['identityObserved','identityBefore','identityAfter','identityNamedAfter']:
   target[key]=copy.deepcopy(original[key]);target[key]['st_nlink']=2;original[key]['st_nlink']=2
 reject('coherent live photo alias still violates independent copy',coherent_photo_alias)
 def absent_standard(a,b):
  value=a['roots']['standardPreferences'];a['roots']['standardPreferences']={'path':value['path'],'absent':True,'ancestorPathBindings':value['ancestorPathBindings']}
 reject('whole standard Preferences absence cannot hide domain',absent_standard)
 expected={k:str(v) for k,v in roots.items()};assert p.bind_roots(before,expected)
 wrong=copy.deepcopy(before);wrong['roots']['standardPreferences']['path']=str(area/'wrong-but-empty')
 try:p.bind_roots(wrong,expected)
 except AssertionError:checks.append({'case':'exact independent role-path binding rejects wrong preference container','accepted':False})
 else:raise AssertionError('Wrong preference container path accepted')
 # A real unexpected empty directory has no leaf bytes; require inventory predicates to catch it.
 (current/'unexpected-empty').mkdir();extra=s.capture(roots)
 try:p.validate_post(before,extra,copy_id)
 except AssertionError:checks.append({'case':'actual unknown empty directory','accepted':False})
 else:raise AssertionError('Unknown empty directory accepted')
 samples={'before':before,'after':after,'terminal':terminal,'unexpectedEmpty':extra}
assert (B/'retained-backend-protocol-r3.py').read_bytes()==source_before
raw=json.dumps({'samples':samples,'sourceFixtureHistory':history_name,'scope':'Actual tiny temporary host OS samples simulating the declared transaction, using known synthetic fixture records from immutable historical poststate; not native/backend acceptance.'},sort_keys=True).encode();rawout.write_bytes(gzip.compress(raw,mtime=0))
result={'status':'PASS pure backend predicates actual synthetic OS endpoints and tampered candidates','protocolBytes':len(source_before),'protocolSHA256':hashlib.sha256(source_before).hexdigest(),'sourceBeforeAfterExact':True,'checks':checks,'raw':rawout.name,'rawDecodedBytes':len(raw),'rawDecodedSHA256':hashlib.sha256(raw).hexdigest(),'temporarySyntheticFixturesRemoved':True,'scope':'Only pure endpoint validator controls; no new native/app/build/current backend acceptance. Candidate tampering explicitly synthetic; actual current live audit still required.','checkedAt':time.time()};output.write_text(json.dumps(result,indent=2)+'\n');print(len(checks),'backend endpoint controls passed')
