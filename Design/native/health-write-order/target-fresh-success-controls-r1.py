"""In-memory synthetic success records; no simulator, preferences or Health IO."""
import base64,copy,gzip,hashlib,importlib.util,json,time
from pathlib import Path
from types import SimpleNamespace
from uuid import UUID
B=Path(__file__).resolve().parent
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
success=module('success_under_test','legacy-target-fresh-success-r1.py')
v=module('strict_tree_validator','legacy-target-change-validation-r3.py')
h=SimpleNamespace(sha=lambda raw:hashlib.sha256(raw).hexdigest(),DATA=b'{synthetic persisted legacy origin damaged')
def encoded(raw):return {'bytes':len(raw),'sha256':h.sha(raw),'base64':base64.b64encode(raw).decode()}
def js(value):return json.dumps(value,sort_keys=True,separators=(',',':')).encode()
started=time.time()-10;at=time.time();stamp='2026-11-08T12:00:00Z'
def uid(n):return str(UUID(int=n))
journal={'version':1,'owner':uid(1),'lifecycle':uid(2),'events':[
 {'id':uid(3),'lifecycle':uid(2),'domain':'water','localID':'synthetic-reset-unstarted-save','generation':uid(4),'action':'save','identity':'sync','acknowledged':[],'components':[{'metric':'water','value':137,'date':815313600}],'requestedAt':815313600},
 {'id':uid(5),'lifecycle':uid(2),'domain':'water','localID':'synthetic-reset-pending-removal','generation':uid(6),'action':'delete','identity':'sync','acknowledged':[],'components':[{'metric':'water','value':257,'date':815313600}],'requestedAt':815313600}]}
rawfiles={name:b'[]' for name in ['chat.json','conversation-selection.json','conversations.json','goals.json','habits.json','profile.json','today.json','water.json','weight.json']}
rawfiles.update({'health-write-intent.json':js(journal),'.health-recovery/'+uid(7)+'/manifest.json':b'{}','.health-recovery/'+uid(7)+'/today.json':b'{}','.health-recovery/'+uid(7)+'/device-intent.json':js(journal)})
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
providerraw=(B/'health-photo-matrix-r1-Lumen-backup-health-matrix-two-legacy.json').read_bytes();provider={'file':'/synthetic/Lumen-backup-health-matrix-two-legacy.json','identity':{'st_ino':42},**encoded(providerraw)}
before=tree(rawfiles,100);first={'current':before,'prior':copy.deepcopy(before),'provider':provider}
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
newfiles[parent+'/manifest.json']=js({'version':2,'createdAt':stamp,'domains':['meals','workouts'],'photos':False,'intent':True,'legacyOrigins':descriptors});newfiles[parent+'/device-intent.json']=js(journal)
record={'observedAt':at,'current':tree(newfiles,101,before),'prior':copy.deepcopy(before),'provider':copy.deepcopy(provider),'residuals':{key:[] for key in ['LumenData.restore-*','LumenData.retired-*','Lumen-reset-fixture-*']}}
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
 ('foreign journal owner',lambda j:j.update(owner=uid(40))),('unchanged lifecycle',lambda j:j.update(lifecycle=uid(2))),('missing pending deletion',lambda j:j['events'].pop()),('new acknowledgement',lambda j:j['events'][1].update(acknowledged=['water'])),('changed deletion identity',lambda j:j['events'][1].update(id=uid(41))),('changed deletion payload',lambda j:j['events'][1]['components'][0].update(value=0)),('old save requeued',lambda j:j['events'][0].update(lifecycle=uid(8))),('save unavailable rewritten',lambda j:j['events'][0].update(issue='unavailable')),('deletion permission unexpected',lambda j:j['events'][1].update(issue='permission'))]:
 run(name,lambda r,m=mutator:replace_file(r,'health-write-intent.json',m))
run('wrong private raw token',lambda r:replace_file(r,parent+'/legacy-origin-meals.json',lambda j:j.update(payload=base64.b64encode(h.DATA).decode())))
run('private intent changed',lambda r:replace_file(r,parent+'/device-intent.json',lambda j:j.update(owner=uid(42))))
run('wrong legacy domains',lambda r:replace_file(r,parent+'/manifest.json',lambda j:j.update(domains=['meals'])))
run('missing prior original',lambda r:r['prior']['files'].pop('chat.json'))
run('provider identity changed',lambda r:r['provider']['identity'].update(st_ino=43))
run('residual stage',lambda r:r['residuals']['LumenData.restore-*'].append('/synthetic/stage'))
run('carried record changed',lambda r:replace_file(r,'profile.json',lambda j:j.append('changed')))
run('old photo identifier reused',lambda r:replace_file(r,'meals.json',lambda j:j[0].update(photoID='synthetic-matrix-photo-a')))
run('extra installed file',lambda r:r['current']['files'].update({'unexpected.json':encoded(b'{}')}))
archive=js({'scope':'Isolated in-memory synthetic records; no actual native success','first':first,'provider':provider,'started':started,'cases':fixtures})
target=B/'source232-fresh-success-controls-r1-fixtures.json.gz';assert not target.exists();target.write_bytes(gzip.compress(archive,mtime=0))
result={'status':'PASS isolated fresh-success retained-record controls','count':len(tests),'accepted':sum(row['actualAcceptance'] for row in tests),'rejected':sum(not row['actualAcceptance'] for row in tests),'cases':tests,'fixtureArchive':{'file':target.name,'bytes':target.stat().st_size,'sha256':h.sha(target.read_bytes()),'decodedBytes':len(archive),'decodedSHA256':h.sha(archive)},'scope':'Pure injected records/real validator only. Not app, process, preferences, LocalStore, Health or native success proof.','checkedAt':time.time()}
(B/'source232-fresh-success-controls-r1.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:value for k,value in result.items() if k!='cases'}))
