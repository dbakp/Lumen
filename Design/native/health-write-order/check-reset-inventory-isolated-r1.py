"""Actual strict inventory predicates with small synthetic files; no app reset."""
import base64, copy, gzip, hashlib, importlib.util, json, plistlib, tempfile, time
from pathlib import Path
BASE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('inventory_reset_evidence',BASE/'legacy-settings-erase-evidence-r2.py')
e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h=e.h
raw=Path(tempfile.mkdtemp(prefix='LumenResetInventoryIsolatedR1-',dir='/tmp'));sha=lambda d:hashlib.sha256(d).hexdigest()
old=h.container
actual=h.load(BASE/'health-capture-state-retry-failure-source220r2-host-audit.json')['before']
initial={k:actual[k] for k in ['profile.json','habits.json']}
base_event={'id':'2B4FB48F-926B-4877-B109-437EFCCFF5BB','lifecycle':'686E8B09-F310-4771-AC2D-F96C3D47513D',
 'domain':'water','localID':'synthetic-reset-pending-removal','identity':'sync','components':[{'metric':'water','value':257,'date':815313600}],
 'generation':'70FA512C-51C0-4C43-98B6-44E497BC4DD3','requestedAt':815313650,'action':'delete','acknowledged':[]}
before={'version':1,'owner':'1EAB27B1-1E17-42B3-A974-03B015D37A5B','lifecycle':base_event['lifecycle'],'events':[base_event,dict(base_event,localID='synthetic-reset-unstarted-save',action='save',id='ED63EF6D-A29A-4918-B8D5-251F16ED50F2')]}
after=copy.deepcopy(before);after['lifecycle']='0664A065-C62C-4691-BFCB-E84AB045A468';after['events']=after['events'][:1];after['events'][0]['generation']='99446840-B7AB-4E82-B9C9-6A8EBAA6E7EE';after['events'][0]['components']=[dict(c,value=0,date=-978307200) for c in base_event['components']]
rows=[]
try:
 for scenario in ['fresh-control','unexpected-file','old-disk-goals','wrong-goal-model','old-water-record','stale-generation','fixed-key-resurrection']:
  folder=raw/scenario;group=folder/'group';root=group/'LumenData';data=folder/'data';root.mkdir(parents=True);(data/'Library/Preferences').mkdir(parents=True)
  h.container=lambda kind,d=data,g=group:{'data':d,'group.com.dbakp.lumen':g}[kind]
  plist=data/'Library/Preferences/com.dbakp.lumen.plist';plist.write_bytes(plistlib.dumps({}))
  for n in e.FRESH_REQUIRED:
   if n in e.FRESH_ARRAYS:value=[]
   elif n=='profile.json':value=json.loads(base64.b64decode(initial[n]['base64']));value.update(name='',onboardingDone=False)
   elif n=='habits.json':value=json.loads(base64.b64decode(initial[n]['base64']))
   elif n=='personal-context.json':value={**dict.fromkeys(['focus','foodPreferences','allergies','limitations','schedule','notes'],''),'includeInAssistant':False}
   elif n=='reminder-preferences.json':value={'enabled':False,'quietStart':21,'quietEnd':8,'showDetails':False}
   elif n=='health-write-intent.json':value=after
   else:raise AssertionError(n)
   (root/n).write_text(json.dumps(value))
  observation={'fixed':{x:{'persistedPresent':False,'effectivePresent':False} for x in ['meals','workouts']},'onboardingDone':False,'profileName':'',
               'goals':copy.deepcopy(e.FRESH_GOALS),'stepGoal':10000,'meals':0,'workouts':0,'water':0,'journal':copy.deepcopy(after),'at':time.time()}
  if scenario=='unexpected-file':(root/'unexpected-old-copy.json').write_text('{"synthetic":"old local data"}')
  if scenario=='old-disk-goals':(root/'goals.json').write_text(json.dumps(dict(e.FRESH_GOALS,stepGoal=6543)))
  if scenario=='wrong-goal-model':observation['goals']['weightKg']=88.5
  if scenario=='old-water-record':(root/'water.json').write_text('[{"id":"synthetic-review-water","ml":137}]')
  if scenario=='stale-generation':
   changed=copy.deepcopy(after);changed['events'][0]['generation']=base_event['generation'];(root/'health-write-intent.json').write_text(json.dumps(changed))
  if scenario=='fixed-key-resurrection':plist.write_bytes(plistlib.dumps(dict.fromkeys(e.KEYS,h.DATA)))
  retained={};failed=False
  try:e.erased(group,observation,before,initial,retained)
  except AssertionError:failed=True
  assert failed==(scenario!='fresh-control'),scenario
  assert retained['tree']['files']
  if scenario=='unexpected-file':assert 'unexpected-old-copy.json' in retained['files']
  if scenario=='old-disk-goals':assert json.loads(base64.b64decode(retained['files']['goals.json']['base64']))['stepGoal']==6543
  if scenario=='fixed-key-resurrection':assert base64.b64decode(retained['fixed'][e.KEYS[0]]['base64'])==h.DATA
  (folder/'actual-retained.json').write_text(json.dumps(retained,indent=2)+'\n')
  rows.append({'case':scenario,'status':'PASS isolated actual predicate expectation','rejected':failed,'actualPayloadFilesRetained':len(retained['tree']['files'])})
finally:h.container=old
files={}
for p in sorted(raw.rglob('*')):
 if p.is_file():
  d=p.read_bytes();files[str(p.relative_to(raw))]={'bytes':len(d),'sha256':sha(d),'base64':base64.b64encode(d).decode()}
archive=BASE/'reset-inventory-isolated-r1-fixtures.json.gz';archive.write_bytes(gzip.compress(json.dumps({'files':files},separators=(',',':')).encode(),mtime=0))
provenance=[]
for n in ['legacy-settings-erase-evidence-r2.py','check-reset-inventory-isolated-r1.py','health-capture-state-retry-failure-source220r2-host-audit.json']:
 d=(BASE/n).read_bytes();provenance.append({'file':str((BASE/n).relative_to(BASE.parents[2])),'bytes':len(d),'sha256':sha(d)})
out={'status':'PASS7 isolated actual predicate cases only; no native/product reset acceptance','cases':rows,'provenance':provenance,
     'fixtureArchive':{'file':archive.name,'bytes':archive.stat().st_size,'sha256':sha(archive.read_bytes()),'payloadFiles':len(files)},
     'temporaryDirectory':str(raw),'scope':'One synthetic fresh control and six deliberate known violations; actual helper executed on isolated small files. No simulator/defaults/Keychain/Health action.','physicalDeviceActions':False,'checkedAt':time.time()}
(BASE/'reset-inventory-isolated-r1-outcome.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps({'status':out['status'],'payloadFiles':len(files),'temporaryDirectory':str(raw)}))
