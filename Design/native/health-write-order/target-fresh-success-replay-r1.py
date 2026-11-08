"""Replay complete retained isolated fixtures against the final validator."""
import base64,copy,gzip,hashlib,importlib.util,json,time
from pathlib import Path
from types import SimpleNamespace
B=Path(__file__).resolve().parent
def module(name,file):
 s=importlib.util.spec_from_file_location(name,B/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
success=module('success_final','legacy-target-fresh-success-r1.py');v=module('tree_final','legacy-target-change-validation-r3.py')
h=SimpleNamespace(sha=lambda raw:hashlib.sha256(raw).hexdigest(),DATA=b'{synthetic persisted legacy origin damaged')
receipt=json.loads((B/'source232-fresh-success-controls-r1.json').read_bytes());fact=receipt['fixtureArchive'];raw=(B/fact['file']).read_bytes()
assert len(raw)==fact['bytes'] and h.sha(raw)==fact['sha256'];decoded=gzip.decompress(raw);assert len(decoded)==fact['decodedBytes'] and h.sha(decoded)==fact['decodedSHA256']
fixture=json.loads(decoded);results=[]
def check(name,record,expected):
 try:success.validate(record,fixture['first'],fixture['provider'],h,v,fixture['started']);actual=True
 except Exception:actual=False
 assert actual is expected,(name,actual);results.append({'name':name,'expectedAcceptance':expected,'actualAcceptance':actual})
for case,wanted in zip(fixture['cases'],receipt['cases']):
 assert case['name']==wanted['name'];check(case['name'],case['record'],wanted['expectedAcceptance'])
def write(record,name,value):
 raw=json.dumps(value,sort_keys=True,separators=(',',':')).encode();row={'bytes':len(raw),'sha256':h.sha(raw),'base64':base64.b64encode(raw).decode()}
 tree=record['current'];tree['files'][name]=row;meta=tree['metadata']['files'][name];meta.update(bytes=len(raw),sha256=h.sha(raw));meta['identity']['st_size']=len(raw)
 for entry in tree['entries']:
  if entry['path']==name:entry['identity']=copy.deepcopy(meta['identity'])
baseline=fixture['cases'][0]['record'];parent=baseline['current']['validation']['newPrivateDirectory'] if 'validation' in baseline['current'] else next(name.rsplit('/',1)[0] for name in baseline['current']['files'] if name.endswith('/legacy-origin-meals.json'))
for name in ['invalid manifest date','boolean envelope schema','changed prior root']:
 record=copy.deepcopy(baseline)
 if name=='changed prior root':record['prior']['rootIdentity']['st_ino']+=1
 else:
  manifestpath=parent+'/manifest.json';manifest=json.loads(base64.b64decode(record['current']['files'][manifestpath]['base64']))
  if name=='invalid manifest date':manifest['createdAt']='invalid'
  else:
   path=parent+'/legacy-origin-meals.json';envelope=json.loads(base64.b64decode(record['current']['files'][path]['base64']));envelope['schemaVersion']=True;write(record,path,envelope);manifest['legacyOrigins']['meals']['sha256']=record['current']['files'][path]['sha256']
  write(record,manifestpath,manifest)
 check(name,record,False)
target=B/'source232-fresh-success-replay-r1.json';assert not target.exists()
out={'status':'PASS final-validator isolated replay','count':len(results),'accepted':sum(row['actualAcceptance'] for row in results),'rejected':sum(not row['actualAcceptance'] for row in results),'cases':results,'inputArchive':fact,'validatorSHA256':h.sha((B/'legacy-target-fresh-success-r1.py').read_bytes()),'scope':'Pure records only, no native/app/process/preferences/Health execution.','checkedAt':time.time()};target.write_text(json.dumps(out,indent=2)+'\n');print(json.dumps({key:value for key,value in out.items() if key!='cases'}))
