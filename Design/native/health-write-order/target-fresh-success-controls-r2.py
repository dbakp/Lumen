"""In-memory synthetic success records; no simulator, preferences or Health IO."""
import base64,copy,gzip,hashlib,importlib.util,json,time
from pathlib import Path
from types import SimpleNamespace
from uuid import UUID
B=Path(__file__).resolve().parent
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
success=module('success_under_test','legacy-target-fresh-success-r2.py')
v=module('strict_tree_validator','legacy-target-change-validation-r3.py')
h=SimpleNamespace(sha=lambda raw:hashlib.sha256(raw).hexdigest(),DATA=b'{synthetic persisted legacy origin damaged')
def encoded(raw):return {'bytes':len(raw),'sha256':h.sha(raw),'base64':base64.b64encode(raw).decode()}
def js(value):return json.dumps(value,sort_keys=True,separators=(',',':')).encode()
started=time.time()-10;at=time.time();stamp='2026-11-08T12:00:00Z'
def uid(n):return str(UUID(int=n))
inputpath=B/'health-legacy-target-change-data-source230r1-host-audit.json';inputraw=inputpath.read_bytes()
assert h.sha(inputraw)=='b9e5838bcd1d830cce0338a7a9a2ecaa60fc0672cb9d91ec0364a8f5a9d485c7'
bound=json.loads(inputraw)['boundaries'][0]['protected']
journal=json.loads(base64.b64decode(bound['current']['files']['health-write-intent.json']['base64']))
rawfiles={name:base64.b64decode(row['base64'],validate=True) for name,row in bound['current']['files'].items()}
def tree(files,inode,old=None):
 facts={};directories=set();entries=[]
 for i,(name,raw) in enumerate(sorted(files.items())):
  identity=copy.deepcopy(old['metadata']['files'][name]['identity']) if old and name in old['files'] else {'st_ino':10000+i,'st_dev':1,'st_mode':33152,'st_nlink':1,'st_size':len(raw),'st_mtime_ns':100}
  identity['st_size']=len(raw);facts[name]={'identity':identity,'bytes':len(raw),'sha256':h.sha(raw)}
  parent=Path(name).parent
  while str(parent)!='.':directories.add(str(parent));parent=parent.parent
 for name in sorted(files):entries.append({'path':name,'kind':'regular','identity':facts[name]['identity']})
 for i,name in enumerate(sorted(directories)):entries.append({'path':name,'kind':'directory','identity':{'st_mode':16832,'st_ino':20000+i}})
 return {'exists':True,'status':'observed','rootIdentity':{'st_ino':inode,'st_dev':1,'st_mode':16832},'files':{name:encoded(raw) for name,raw in files.items()},'metadata':{'files':facts,'directories':sorted(directories)},'entries':entries}
provider=copy.deepcopy(bound['provider']);providerraw=base64.b64decode(provider['base64'],validate=True)
assert providerraw==(B/'health-photo-matrix-r1-Lumen-backup-health-matrix-two-legacy.json').read_bytes()
before=copy.deepcopy(bound['current']);first=copy.deepcopy(bound)
source=json.loads(providerraw);snapshot=json.loads(base64.b64decode(source['payload']))
newfiles=copy.deepcopy(rawfiles);newjournal=copy.deepcopy(journal);newjournal['lifecycle']=uid(8);newfiles['health-write-intent.json']=js(newjournal)
meals=copy.deepcopy(snapshot['meals']);photos={}
for i,meal in enumerate(meals):
 old=meal['photoID'];meal['photoID']=uid(20+i);name='photos/'+meal['photoID']+'.jpg';newfiles[name]=base64.b64decode(snapshot['photos'][old]);photos[name]=h.sha(newfiles[name])
newfiles['meals.json']=js(meals);newfiles['workouts.json']=b'[]'
receipt={'source':'selected-file:'+provider['sha256'],'domains':['meals','workouts'],'recordDigests':{name:h.sha(newfiles[name]) for name in ['meals.json','workouts.json']},'photoDigests':photos,'recoveredAt':__import__('datetime').datetime.fromtimestamp(at,__import__('datetime').timezone.utc).isoformat(),'fileSource':{'fileName':Path(provider['file']).name,'format':'legacyJSONBackup','byteCount':provider['bytes'],'sha256':provider['sha256']},'omittedPhotoCount':0,'reviewedPhotos':{key:{'byteCount':len(base64.b64decode(value)),'sha256':h.sha(base64.b64decode(value))} for key,value in snapshot['photos'].items()}}
receiptname='.health-recovery-history/'+uid(30)+'.json';newfiles[receiptname]=js(receipt)
parent='.health-recovery/'+uid(31);descriptors={}
for domain,wanted in [('meals',b'{synthetic newer persisted meals damaged'),('workouts',h.DATA)]:
 name='legacy-origin-'+domain+'.json';raw=js({'schemaVersion':1,'domain':domain,'key':'lumen.health.'+domain+'.v1','type':'data','payload':base64.b64encode(wanted).decode(),'sha256':h.sha(wanted)});newfiles[parent+'/'+name]=raw;descriptors[domain]={'file':name,'sha256':h.sha(raw)}
newfiles[parent+'/manifest.json']=js({'version':2,'createdAt':stamp,'domains':['meals','workouts'],'photos':False,'intent':True,'legacyOrigins':descriptors});newfiles[parent+'/device-intent.json']=rawfiles['health-write-intent.json']
priorparent='.health-recovery/'+uid(32)
for name,priorname in [('meals.json','meals.json'),('workouts.json','workouts.json'),('device-intent.json','health-write-intent.json')]:
 newfiles[priorparent+'/'+name]=base64.b64decode(first['prior']['files'][priorname]['base64'],validate=True)
newfiles[priorparent+'/manifest.json']=js({'version':1,'createdAt':stamp,'domains':['meals','workouts'],'photos':False,'intent':True})
group='/synthetic/group'
record={'observedAt':at,'group':group,'current':tree(newfiles,before['rootIdentity']['st_ino']+1,before),'provider':copy.deepcopy(provider),'namespace':{'group':group,'previous':{'path':group+'/LumenData.previous','exists':False,'errno':2},'retired':[],'restore':[],'resetFixtures':[]}}
def replace_file(r,name,mutator):
 files={key:base64.b64decode(value['base64']) for key,value in r['current']['files'].items()};value=json.loads(files[name]);mutator(value);files[name]=js(value);r['current']=tree(files,101,before)
tests=[];fixtures=[]
def run(name,mutator,accept=False):
 r=copy.deepcopy(record);mutator(r)
 try:success.validate(r,first,provider,h,v,started);passed=True;error=None
 except Exception as e:passed=False;error=type(e).__name__
 assert passed==accept,(name,passed,error)
 tests.append({'name':name,'expectedAcceptance':accept,'actualAcceptance':passed,'errorType':error});fixtures.append({'name':name,'record':r})
run('valid complete fresh commit',lambda r:None,True)
run('pending deletion unavailable only',lambda r:replace_file(r,'health-write-intent.json',lambda j:j['events'][1].update(issue='unavailable')),True)
for name,mutator in [
 ('wrong receipt source',lambda r:r.update(source='wrong')),('missing receipt domain',lambda r:r.update(domains=['meals'])),('omission',lambda r:r.update(omittedPhotoCount=1)),('boolean omission',lambda r:r.update(omittedPhotoCount=False)),('wrong photo digests',lambda r:r.update(photoDigests={})),('wrong record digests',lambda r:r.update(recordDigests={})),('wrong reviewed photos',lambda r:r.update(reviewedPhotos={})),('foreign file source',lambda r:r['fileSource'].update(sha256='0'*64)),('extra receipt field',lambda r:r.update(unreviewed=True))]:
 run(name,lambda r,m=mutator:replace_file(r,receiptname,m))
for name,mutator in [
 ('foreign journal owner',lambda j:j.update(owner=uid(40))),('unchanged lifecycle',lambda j:j.update(lifecycle=journal['lifecycle'])),('missing pending deletion',lambda j:j['events'].pop()),('new acknowledgement',lambda j:j['events'][1].update(acknowledged=['water'])),('changed deletion identity',lambda j:j['events'][1].update(id=uid(41))),('changed deletion payload',lambda j:j['events'][1]['components'][0].update(value=0)),('old save requeued',lambda j:j['events'][0].update(lifecycle=uid(8))),('save unavailable rewritten',lambda j:j['events'][0].update(issue='unavailable')),('deletion permission unexpected',lambda j:j['events'][1].update(issue='permission'))]:
 run(name,lambda r,m=mutator:replace_file(r,'health-write-intent.json',m))
run('wrong private raw token',lambda r:replace_file(r,parent+'/legacy-origin-meals.json',lambda j:j.update(payload=base64.b64encode(h.DATA).decode())))
run('private intent changed',lambda r:replace_file(r,parent+'/device-intent.json',lambda j:j.update(owner=uid(42))))
run('wrong legacy domains',lambda r:replace_file(r,parent+'/manifest.json',lambda j:j.update(domains=['meals'])))
run('unexpected previous present',lambda r:r['namespace']['previous'].update(exists=True))
run('provider identity changed',lambda r:r['provider']['identity'].update(st_ino=43))
run('residual stage',lambda r:r['namespace']['restore'].append('/synthetic/stage'))
run('carried record changed',lambda r:replace_file(r,'profile.json',lambda j:j.update(unexpected=True)))
run('old photo identifier reused',lambda r:replace_file(r,'meals.json',lambda j:j[0].update(photoID='synthetic-matrix-photo-a')))
run('extra installed file',lambda r:r['current']['files'].update({'unexpected.json':encoded(b'{}')}))
for label,name in [('prior meals changed','meals.json'),('prior workouts changed','workouts.json'),('prior intent changed','device-intent.json')]:
 run(label,lambda r,n=name:replace_file(r,priorparent+'/'+n,lambda value:value.append('changed') if isinstance(value,list) else value.update(unexpected=True)))
run('prior v1 manifest domains wrong',lambda r:replace_file(r,priorparent+'/manifest.json',lambda j:j.update(domains=['meals'])))
run('prior v1 false photos claim',lambda r:replace_file(r,priorparent+'/manifest.json',lambda j:j.update(photos=True)))
run('prior v1 intent omitted',lambda r:replace_file(r,priorparent+'/manifest.json',lambda j:j.update(intent=False)))
run('prior v1 boolean version',lambda r:replace_file(r,priorparent+'/manifest.json',lambda j:j.update(version=True)))
run('prior private copy missing',lambda r:r['current']['files'].pop(priorparent+'/meals.json'))
run('retired namespace not settled',lambda r:r['namespace']['retired'].append({'path':group+'/LumenData.retired-'+uid(33),'exists':False,'errno':2}))
run('foreign namespace group',lambda r:r['namespace'].update(group='/foreign'))
archive=js({'scope':'Isolated records constructed from pinned actual synthetic current13/prior13; no native success','first':first,'provider':provider,'started':started,'cases':fixtures})
target=B/'source233-fresh-success-controls-r2-fixtures.json.gz';assert not target.exists();target.write_bytes(gzip.compress(archive,mtime=0))
result={'status':'PASS isolated fresh-success retained-record controls','count':len(tests),'accepted':sum(row['actualAcceptance'] for row in tests),'rejected':sum(not row['actualAcceptance'] for row in tests),'cases':tests,'fixtureArchive':{'file':target.name,'bytes':target.stat().st_size,'sha256':h.sha(target.read_bytes()),'decodedBytes':len(archive),'decodedSHA256':h.sha(archive)},'input':{'file':inputpath.name,'bytes':len(inputraw),'sha256':h.sha(inputraw)},'scope':'Pure injected records from pinned actual baseline/real validator only. Not app, process, preferences, LocalStore, Health or native success proof.','checkedAt':time.time()}
(B/'source233-fresh-success-controls-r2.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:value for k,value in result.items() if k!='cases'}))
