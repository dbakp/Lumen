"""Small side-effect-free strict helpers for the single synthetic mixed-origin case."""
import base64, gzip, hashlib, json, os, plistlib, stat, subprocess
from pathlib import Path
BASE = Path(__file__).resolve().parent
REPO = BASE.parents[2]
DEVICE = '5C4C4A6C-4D9E-4181-8794-E3925C1A7EA7'
SAFE_DEVICE = '5C4C4A6C-4D9E-4181-8794-E3925C1A7EA7'
NAME = 'Lumen-backup-health-matrix-two-legacy.json'
DICTIONARY = {'synthetic': 'Synthetic unsupported saved meals'}
DATA = b'{synthetic persisted legacy origin damaged'
SUFFIXES = ['source','healthy-water','healthy-goals','mixed-off','workouts-selected','confirmation','not-now','held-1','observed-1','success','post-success','parent','relaunch-review','relaunch-parent']
sha = lambda b: hashlib.sha256(b).hexdigest()
def row(data):
    return {'bytes':len(data),'sha256':sha(data),'base64':base64.b64encode(data).decode()}
def read(path, limit=256*1024):
    path=Path(path); facts=path.lstat()
    assert stat.S_ISREG(facts.st_mode) and not path.is_symlink() and facts.st_size<=limit, str(path)
    return path.read_bytes()
def load(path): return json.loads(read(path, 4*1024*1024))
def container(kind):
    assert DEVICE == SAFE_DEVICE, 'Only the approved dedicated synthetic simulator'
    return Path(subprocess.check_output(['xcrun','simctl','get_app_container',DEVICE,'com.dbakp.lumen',kind],text=True).strip())
def snapshot(root):
    assert stat.S_ISDIR(root.lstat().st_mode) and not root.is_symlink()
    result={}; total=0
    for parent,dirs,files in os.walk(root,followlinks=False):
        for name in dirs: assert not (Path(parent)/name).is_symlink()
        for name in files:
            data=read(Path(parent)/name);total+=len(data);assert total<=2*1024*1024
            result[str((Path(parent)/name).relative_to(root))]=row(data)
    return result
def directories(root):
    result=[]
    assert stat.S_ISDIR(root.lstat().st_mode) and not root.is_symlink()
    for parent,dirs,files in os.walk(root,followlinks=False):
        for name in dirs:
            child=Path(parent)/name
            assert stat.S_ISDIR(child.lstat().st_mode) and not child.is_symlink()
            result.append(str(child.relative_to(root)))
    return sorted(result)
def allowed_directories(before_dirs, files):
    result=set(before_dirs)
    for name in files:
        parent=Path(name).parent
        while str(parent)!='.':
            result.add(str(parent));parent=parent.parent
    return sorted(result)
FIELDS=['st_ino','st_dev','st_mode','st_nlink','st_size','st_mtime_ns']
def identity(path):
    facts=Path(path).lstat();assert not Path(path).is_symlink()
    return {key:getattr(facts,key) for key in FIELDS}
def metadata(root):
    return {name:identity(root/name) for name in snapshot(root)}
def fixed(expected, observed=None):
    # Only these two known synthetic keys are retained. This diagnostic JSON is
    # not original plist bytes or a general unsupported-value codec.
    values=plistlib.loads(read(container('data')/'Library/Preferences/com.dbakp.lumen.plist'))
    assert expected['bundle']=='com.dbakp.lumen' and expected['kind']=='mixed-data'
    assert set(expected['values'])=={'meals','workouts'}
    if observed is None: observed={}
    for domain in ['meals','workouts']:
        key='lumen.health.'+domain+'.v1';value=values.get(key)
        observed[domain]={'key':key,'actualType':type(value).__name__}
        if isinstance(value,bytes): observed[domain].update({'type':'data',**row(value)})
        elif isinstance(value,str): observed[domain].update({'type':'stringUTF16LE',**row(value.encode('utf-16-le'))})
        elif isinstance(value,dict) and all(type(k) is str and type(v) is str for k,v in value.items()):
            diagnostic=json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
            observed[domain].update({'type':'propertyListDictionary','value':value,**row(diagnostic)})
        else: observed[domain]['classification']='missing' if value is None else 'unsupported known-key value'
        if domain=='meals':
            assert type(value) is dict and value==DICTIONARY
            raw=json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
            kind='propertyListDictionary'
        else:
            assert type(value) is bytes
            raw=value;kind='data';assert raw==DATA
        observed[domain].update({'type':kind,**row(raw)})
        want=expected['values'][domain]
        assert want['key']==key and want['type']==kind
        assert base64.b64decode(want['payload'],validate=True)==raw
    return observed

def verify_inputs(source_name, build_name):
    source=load(BASE/source_name)
    archive=json.loads(gzip.decompress(read(BASE/(source_name+'.gz'),8*1024*1024)))
    count=0
    for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
        for name,want in source[group].items():
            data=read(REPO/name,4*1024*1024)
            archived=archive[key][name].encode() if key=='files' else base64.b64decode(archive[key][name],validate=True)
            assert data==archived and len(data)==want['bytes'] and sha(data)==want['sha256'],name
            count+=1
    build=load(BASE/build_name);assert build['source']==source_name and build['buildExit']==0
    test=Path(build['testBinary']);app=test.parents[3]/'Lumen.app/Lumen'
    for path,size,digest in [(app,'binaryBytes','sha256'),(test,'testBinaryBytes','testBinarySHA256')]:
        data=read(path,64*1024*1024);assert len(data)==build[size] and sha(data)==build[digest]
    return {'source':source_name,'build':build_name,'inputs':count,'app':row(read(app,64*1024*1024))|{'base64':None},'testSHA256':build['testBinarySHA256']}
def installed(build_name):
    build=load(BASE/build_name);data=read(container('app')/'Lumen',64*1024*1024)
    assert len(data)==build['binaryBytes'] and sha(data)==build['sha256']
    return {'path':str(container('app')/'Lumen'),'bytes':len(data),'sha256':sha(data)}
def validate_context(expected):
    assert DEVICE == SAFE_DEVICE and expected['device'] == SAFE_DEVICE
    assert expected['input'] == str(BASE/'health-photo-matrix-r1-Lumen-backup-health-matrix-two-legacy.json')
    target = REPO.parents[2]/'Library/Developer/CoreSimulator/Devices'/SAFE_DEVICE/'data/Containers/Shared/AppGroup/1E143EEB-A0AC-424A-AF23-ACA91DD19451/File Provider Storage'/NAME
    assert expected['seeded'] == str(target)
    assert type(expected['bytes']) is int and expected['bytes'] == 4992
    assert expected['sha256'] == '80d236abd21b33a3d012d3287a0606e699d53ddc18a9e4263a635cb899629078'
    wanted = expected['identity']
    assert set(wanted) == set(FIELDS)
    assert all(type(wanted[k]) is int and wanted[k] > 0 for k in FIELDS)
    assert wanted['st_mode'] == 33152 and wanted['st_nlink'] == 1 and wanted['st_size'] == 4992
    assert wanted['st_ino'] == 46084867 and wanted['st_dev'] == 16777233 and wanted['st_mtime_ns'] == 1794129209803882773
    return target

def provider():
    expected = load(BASE/'source224-reset-provider-context.json')
    path = validate_context(expected)
    facts = identity(path); data = read(path)
    assert facts == expected['identity']
    assert len(data) == expected['bytes'] and sha(data) == expected['sha256']
    assert data == read(BASE/'health-photo-matrix-r1-Lumen-backup-health-matrix-two-legacy.json')
    return {'file':str(path),'identity':facts,**row(data)}

def verify_host_source(source_name):
    assert Path(source_name).name == source_name and source_name.endswith('.json')
    source = load(BASE/source_name)
    archive = json.loads(gzip.decompress(read(BASE/(source_name+'.gz'),8*1024*1024)))
    count = 0
    for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
        assert set(source[group]) == set(archive[key])
        for name,want in source[group].items():
            data = read(REPO/name,4*1024*1024)
            archived = archive[key][name].encode() if key == 'files' else base64.b64decode(archive[key][name],validate=True)
            assert data == archived and len(data) == want['bytes'] and sha(data) == want['sha256'], name
            count += 1
    assert DEVICE == SAFE_DEVICE
    for name in ['health-mixed-ineligible-evidence-r2.py','health-mixed-ineligible-driver-r2.py','check-mixed-ineligible-evidence-r2.py','source245-safe-mixed-context-r1-plan.json']:
        assert str((BASE/name).relative_to(REPO)) in source['files']
    plan = load(BASE/'source245-safe-mixed-context-r1-plan.json')
    assert plan['compiledCase']['source'] == 'durable-source-r244.json' and plan['compiledCase']['build'] == 'health-target-change-source244-r1-build.json'
    for name,wanted in plan['compiledCase']['bindings'].items():
        data = read(BASE/name,8*1024*1024)
        assert len(data) == wanted['bytes'] and sha(data) == wanted['sha256'], name
    validate_context(load(BASE/'source224-reset-provider-context.json'))
    return {'source':source_name,'bindings':count,'manifestSHA256':sha(read(BASE/source_name)),'caseSource':plan['compiledCase']['source'],'build':plan['compiledCase']['build']}

def owned(pid):
    result={}
    for path in (container('data')/'tmp').glob('LumenBackupWork-v1-'+str(pid)+'-*'):
        marker=load(path/'.lumen-workspace-owner.json')
        assert marker['pid']==pid and marker['version']==1 and path.name=='LumenBackupWork-v1-'+str(pid)+'-'+marker['id']
        result[str(path)]={'owner':marker,'files':snapshot(path)}
    return result
def selected(started):
    candidates=[]; original=provider()
    for path in (container('data')/'tmp').glob('LumenBackupWork-v1-*'):
        if not (path/'selected-backup').exists():continue
        markerpath=path/'.lumen-workspace-owner.json';marker=load(markerpath)
        if markerpath.stat().st_mtime<started:continue
        command=subprocess.check_output(['ps','-p',str(marker['pid']),'-o','comm='],text=True).strip()
        assert Path(command)==container('app')/'Lumen'
        data=read(path/'selected-backup');assert row(data)=={k:original[k] for k in ['bytes','sha256','base64']}
        assert identity(path/'selected-backup')['st_ino']!=original['identity']['st_ino']
        candidates.append({'directory':str(path),'owner':marker,'identity':identity(path/'selected-backup'),**row(data)})
    assert len(candidates)==1,candidates
    source=candidates[0];workspaces=owned(source['owner']['pid']);assert len(workspaces)==2
    return {'source':source,'workspaces':workspaces}
def source_exact(observation):
    source=observation['source'];path=Path(source['directory'])/'selected-backup'
    assert identity(path)==source['identity'] and row(read(path))=={k:source[k] for k in ['bytes','sha256','base64']}
    assert owned(source['owner']['pid'])==observation['workspaces']
    provider()
def preparation(root,before,previous):
    current=snapshot(root)
    assert all(current.get(k)==v for k,v in before.items())
    extra=set(current)-set(before);manifests=[k for k in extra if k.endswith('/manifest.json')]
    assert len(manifests)==1
    name=manifests[0];directory=Path(name).parent;manifest=load(root/name)
    assert str(directory).startswith('.health-recovery/')
    assert manifest['version']==1 and manifest['domains']==['workouts'] and manifest['intent'] is True and manifest['photos'] is False
    assert extra=={str(directory/k) for k in ['manifest.json','workouts.json','device-intent.json']}
    assert current[str(directory/'workouts.json')]==previous['workouts.json']
    assert current[str(directory/'device-intent.json')]==previous['health-write-intent.json']
    return {'manifest':manifest,'files':{k:current[k] for k in sorted(extra)}}
def committed(root,before,priorcopy,expected,observed):
    current=snapshot(root);assert (root/'workouts.json').read_bytes()==b'[]' and not (root/'meals.json').exists()
    for key,value in before.items():
        if key!='health-write-intent.json':assert current[key]==value,key
    for key,value in priorcopy['files'].items():assert current[key]==value
    receipts=list((root/'.health-recovery-history').glob('*.json'));assert len(receipts)==1
    receipt=load(receipts[0]);original=provider()
    assert receipt['fileSource']=={'fileName':NAME,'format':'legacyJSONBackup','byteCount':4992,'sha256':original['sha256']}
    assert receipt['source']=='selected-file:'+original['sha256'] and receipt['domains']==['workouts']
    assert receipt['recordDigests']=={'workouts.json':sha(b'[]')} and receipt['photoDigests']=={} and receipt['reviewedPhotos']=={} and receipt['omittedPhotoCount']==0
    manifests=[p for p in (root/'.health-recovery').glob('*/manifest.json') if load(p)['version']==2]
    assert len(manifests)==1
    path=manifests[0];manifest=load(path);directory=path.parent
    assert manifest['domains']==['workouts'] and set(manifest['legacyOrigins'])=={'workouts'} and manifest['photos'] is False and manifest['intent'] is True
    assert {p.name for p in directory.iterdir()}=={'manifest.json','device-intent.json','legacy-origin-workouts.json'}
    assert read(directory/'device-intent.json')==base64.b64decode(before['health-write-intent.json']['base64'])
    data=read(directory/'legacy-origin-workouts.json');envelope=json.loads(data)
    assert set(envelope)=={'schemaVersion','domain','key','type','payload','sha256'}
    assert envelope=={'schemaVersion':1,'domain':'workouts','key':'lumen.health.workouts.v1','type':'data','payload':base64.b64encode(DATA).decode(),'sha256':sha(DATA)}
    assert manifest['legacyOrigins']['workouts']=={'file':'legacy-origin-workouts.json','sha256':sha(data)}
    allowed=set(before)|set(priorcopy['files'])|{'workouts.json',str(receipts[0].relative_to(root))}|{str(p.relative_to(root)) for p in directory.iterdir()}
    assert set(current)==allowed,(set(current)-allowed,allowed-set(current))
    old=json.loads(base64.b64decode(before['health-write-intent.json']['base64']));new=load(root/'health-write-intent.json')
    assert old['owner']==new['owner'] and old['lifecycle']!=new['lifecycle'] and old['events']==new['events']==[]
    return {'tree':current,'receipt':receipt,'v2':{'directory':str(directory),'manifest':manifest,'envelope':envelope,'outer':row(data)},'fixed':fixed(expected,observed)}
def events(group):
    value=load(group/'Lumen-legacy-origin-review-events.json')['events']
    return value
