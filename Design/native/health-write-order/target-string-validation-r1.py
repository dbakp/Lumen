"""Readonly validators for retained target-change evidence, no PASS-label trust."""
import base64
import json
from pathlib import PurePosixPath
import stat

import importlib.util
from pathlib import Path
_codec_spec=importlib.util.spec_from_file_location('strict_string_codec',Path(__file__).resolve().parent/'target-string-codec-r1.py')
_codec=importlib.util.module_from_spec(_codec_spec);_codec_spec.loader.exec_module(_codec)
OLD=_codec.OLD
NEW=_codec.NEW

def payload(row,h,limit=2*1024*1024):
    raw=base64.b64decode(row['base64'],validate=True)
    assert len(raw)<=limit and len(raw)==row['bytes'] and h.sha(raw)==row['sha256']
    return raw

def tree(row,h):
    assert row['exists'] is True and row['status']=='observed'
    assert stat.S_ISDIR(row['rootIdentity']['st_mode'])
    files=row['files'];meta=row['metadata'];assert set(files)==set(meta['files'])
    directories=set()
    for name,value in files.items():
        path=PurePosixPath(name);assert not path.is_absolute() and '..' not in path.parts and str(path)==name
        raw=payload(value,h,256*1024);facts=meta['files'][name]
        assert facts['bytes']==len(raw) and facts['sha256']==h.sha(raw)
        assert stat.S_ISREG(facts['identity']['st_mode']) and facts['identity']['st_size']==len(raw)
        parent=path.parent
        while str(parent)!='.':directories.add(str(parent));parent=parent.parent
    assert len(meta['directories'])==len(set(meta['directories']))
    assert set(meta['directories'])==directories
    entries=row['entries'];assert len(entries)==len(files)+len(directories)
    assert {r['path'] for r in entries}==set(files)|directories
    for entry in entries:
        if entry['path'] in files:
            assert entry['kind']=='regular' and entry['identity']==meta['files'][entry['path']]['identity']
        else:assert entry['kind']=='directory' and stat.S_ISDIR(entry['identity']['st_mode'])
    assert sum(r['bytes'] for r in files.values())<=2*1024*1024

def protected(row,first,h):
    for name in ['current','prior']:
        tree(row[name],h)
        for key in ['rootIdentity','files','metadata']:assert row[name][key]==first[name][key],(name,key)
    assert row['provider']==first['provider'] and not any(row['residuals'].values())
    assert set(row['residuals'])=={'LumenData.restore-*','LumenData.retired-*','Lumen-reset-fixture-*'}

def fixed(row,wanted,h,ob):
    assert row['healthConnected'] is None or row['healthConnected'] is False
    assert set(row['fixed'])==set(ob.KEYS)
    for key in ob.KEYS:
        value=row['fixed'][key];raw=wanted if key==ob.KEYS[0] else OLD
        assert value['present'] is True and value['type']=='str' and not value.get('oversize')
        assert value['bytes']==len(raw) and value['sha256']==h.sha(raw)
        assert base64.b64decode(value['base64'],validate=True)==raw
    assert row['classification']==('new' if wanted==ob.NEW else 'old') and 'error' not in row
    assert type(row['plistBytes']) is int and 0<row['plistBytes']<=256*1024
    assert len(row['plistSHA256'])==64

def persistence(row,h,ob):
    assert [row[k] for k in ['budgetSeconds','intervalSeconds','stableSamples','stableSpanSeconds']]==[10,0.1,3,0.2]
    samples=row['samples'];assert 3<=len(samples)<=102
    previous=0;streak=[]
    for sample in samples:
        assert previous<=sample['elapsed']<=sample['completedElapsed']<10
        previous=sample['completedElapsed']
        assert sample['classification'] in ['old','new']
        fixed(sample,ob.NEW if sample['classification']=='new' else OLD,h,ob)
        if sample['classification']=='new':streak.append(sample['completedElapsed'])
        else:streak=[]
    assert len(streak)>=3 and streak[-1]-streak[0]>=0.2
    assert row['acceptedElapsed']==samples[-1]['completedElapsed']
    assert row['status']=='PASS bounded exact new-value observations'

def selection(row,provider,pid,h):
    source=row['source'];workspaces=row['workspaces']
    assert source['owner']['pid']==pid and source['directory'] in workspaces and len(workspaces)==2
    assert source['identity']['st_ino']!=provider['identity']['st_ino']
    assert payload(source,h)==payload(provider,h)==h.read(h.BASE/('health-photo-matrix-r1-'+h.NAME))
    for path,workspace in workspaces.items():
        owner=workspace['owner'];assert owner['pid']==pid and owner['version']==1
        assert PurePosixPath(path).name=='LumenBackupWork-v1-'+str(pid)+'-'+owner['id']
        assert json.loads(payload(workspace['files']['.lumen-workspace-owner.json'],h))==owner
        for value in workspace['files'].values():payload(value,h)
    assert workspaces[source['directory']]['owner']==source['owner']
    assert payload(workspaces[source['directory']]['files']['selected-backup'],h)==payload(provider,h)

def cleanup(row,selection):
    assert row['rootsAbsent'] is True and row['hostDeletedWorkspace'] is False
    assert set(row['roots'])==set(selection['workspaces'])
    assert all(path not in row['noOpenPaths'] for path in row['roots'])

def all_payloads(value,h,metadata_app,path=()):
    """Only preflight.app is deliberately metadata-only, bound to fresh inputs."""
    if isinstance(value,dict):
        if {'bytes','sha256','base64'}<=set(value):
            if path==('preflight','app'):
                assert value==metadata_app and value['base64'] is None
                assert type(value['bytes']) is int and value['bytes']>0
                assert len(value['sha256'])==64 and all(c in '0123456789abcdef' for c in value['sha256'])
            else:payload(value,h,64*1024*1024)
        for key,child in value.items():all_payloads(child,h,metadata_app,path+(key,))
    elif isinstance(value,list):
        for index,child in enumerate(value):all_payloads(child,h,metadata_app,path+(index,))

def bootstrap_fixed(row,h):
    keys=['lumen.health.meals.v1','lumen.health.workouts.v1']
    assert 'error' not in row and row['healthConnected'] in [None,False]
    assert row['healthConnected'] is None or row['healthConnected'] is False
    assert set(row['keys'])==set(keys) and row['knownPath'].endswith('/com.dbakp.lumen.plist')
    if row['pathExists']:
        assert row['identityBefore']==row['identityAfter']
        assert stat.S_ISREG(row['identityBefore']['st_mode'])
        assert type(row['plistBytes']) is int and 0<row['plistBytes']<=256*1024
        assert row['identityBefore']['st_size']==row['plistBytes']
        assert len(row['plistSHA256'])==64 and all(c in '0123456789abcdef' for c in row['plistSHA256'])
    else:
        assert row['pathExists'] is False
        assert not any(r['present'] for r in row['keys'].values())
    ready=True
    for value in row['keys'].values():
        assert not value.get('oversize')
        if value['present']:
            assert value['type']=='str' and value['bytes']==len(OLD) and value['sha256']==h.sha(OLD)
            assert base64.b64decode(value['base64'],validate=True)==OLD
        else:
            ready=False;assert value=={'present':False,'type':'NoneType'}
    assert row['classification']==('both-old' if ready else 'initial-missing')
    return ready

def bootstrap_context(row,reference,h):
    assert payload(row['native'],h,128*1024)==payload(reference['nativeCheckpoint'],h,128*1024)
    assert row['native']['file']==reference['nativeCheckpoint']['file']
    assert row['nativeIdentity']==reference['nativeCheckpoint']['identity']
    assert row['processCommand']==reference['process']['executable']
    assert row['currentRootIdentity']==reference['protected']['current']['rootIdentity']
    assert row['priorRootIdentity']==reference['protected']['prior']['rootIdentity']
    assert row['provider']=={k:reference['protected']['provider'][k] for k in ['file','identity','bytes','sha256']}
    assert row['installed']==reference['installed'] and row['ownedPaths']==[]

def bootstrap(row,reference,h):
    assert [row[k] for k in ['budgetSeconds','intervalSeconds','stableSamples','stableSpanSeconds']]==[10,0.1,3,0.2]
    assert row['scope']=='initial-only actual UI checkpoint; missing or exact original String only'
    samples=row['samples'];assert 3<=len(samples)<=102
    previous=0;streak=[];path=None
    for sample in samples:
        assert 'error' not in sample and previous<=sample['elapsed']<=sample['completedElapsed']<10
        previous=sample['completedElapsed']
        bootstrap_context(sample['context'],reference,h)
        ready=bootstrap_fixed(sample['fixed'],h)
        if path is None:path=sample['fixed']['knownPath']
        assert path==sample['fixed']['knownPath']
        if ready:streak.append(sample['completedElapsed'])
        else:streak=[]
    assert len(streak)>=3 and streak[-1]-streak[0]>=0.2
    assert row['acceptedElapsed']==samples[-1]['completedElapsed']
    assert row['status']=='PASS bounded initial exact-old presence'
