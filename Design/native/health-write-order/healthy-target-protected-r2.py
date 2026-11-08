"""Exact known healthy-current-file facts, preserving all prior protected inputs."""
import base64,json,stat
from pathlib import Path,PurePosixPath
HEALTHY=(Path(__file__).resolve().parent/'healthy-target-current-meal-r1.json').read_bytes()
KEYS=['st_ino','st_dev','st_mode','st_nlink','st_size','st_mtime_ns']
def native_leaf(row,root,exists,h):
    root=PurePosixPath(root);assert root.is_absolute() and root.name=='LumenData' and '..' not in root.parts
    assert row['path']==str(root/'meals.json') and row['exists'] is exists
    if not exists:
        assert row=={'path':str(root/'meals.json'),'exists':False,'errno':2};return
    assert set(row)=={'path','exists','errno','identity','bytes','sha256','payload'} and row['errno']==0
    assert type(row['bytes']) is int and row['bytes']==len(HEALTHY) and row['sha256']==h.sha(HEALTHY)
    assert base64.b64decode(row['payload'],validate=True)==HEALTHY
    facts=row['identity'];assert set(facts)==set(KEYS) and all(type(facts[k]) is int for k in KEYS)
    assert stat.S_ISREG(facts['st_mode']) and facts['st_size']==len(HEALTHY) and facts['st_nlink']>=1 and facts['st_ino']>0 and facts['st_dev']>0

def validate(row,first,native,h,v,reference=None):
    for name in ['current','prior']:v.tree(row[name],h)
    for key in ['rootIdentity','files','metadata']:assert row['prior'][key]==first['prior'][key]
    assert row['provider']==first['provider'] and row['residuals']==first['residuals'] and not any(row['residuals'].values())
    before=first['current'];current=row['current'];assert len(before['files'])==13 and len(current['files'])==14
    assert set(current['files'])==set(before['files'])|{'meals.json'} and 'workouts.json' not in current['files']
    for name,wanted in before['files'].items():
        assert current['files'][name]==wanted and current['metadata']['files'][name]==before['metadata']['files'][name]
    assert current['metadata']['directories']==before['metadata']['directories']
    for key in ['st_ino','st_dev','st_mode']:assert current['rootIdentity'][key]==before['rootIdentity'][key]
    # The exact one known regular-file addition can change the directory's
    # reported link count. This is not permission for arbitrary root changes.
    old_links=before['rootIdentity']['st_nlink'];new_links=current['rootIdentity']['st_nlink']
    assert type(old_links) is int and old_links>0 and type(new_links) is int
    assert new_links in {old_links,old_links+1}
    for key in ['st_size','st_mtime_ns']:assert type(current['rootIdentity'][key]) is int and current['rootIdentity'][key]>0
    native_leaf(native,PurePosixPath(native['path']).parent,True,h)
    assert v.payload(current['files']['meals.json'],h)==HEALTHY
    assert current['metadata']['files']['meals.json']['identity']==native['identity']
    if reference is not None:
        for name in ['current','prior']:
            for key in ['rootIdentity','files','metadata']:assert row[name][key]==reference[name][key]
    return row

def collect(group,sink,first,native,h,e,v,reference=None):
    root=Path(group)/'LumenData';assert native['path']==str(root/'meals.json')
    for name,path in [('current',root),('prior',root.with_suffix('.previous'))]:
        sink[name]={};e.e.observe_tree(path,sink[name])
    sink['provider']=h.provider();sink['residuals']={p:[str(x) for x in Path(group).glob(p)] for p in ['LumenData.restore-*','LumenData.retired-*','Lumen-reset-fixture-*']}
    return validate(sink,first,native,h,v,reference)
