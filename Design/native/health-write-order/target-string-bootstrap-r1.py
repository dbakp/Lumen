"""Initial-only read-only known-key bootstrap after an actual native UI checkpoint.
Post-mutation observation intentionally continues to use its unchanged observer.
"""
import base64
import os
import plistlib
import stat
import time
import traceback
import importlib.util
from pathlib import Path
_codec_spec=importlib.util.spec_from_file_location('strict_string_codec',Path(__file__).resolve().parent/'target-string-codec-r1.py')
_codec=importlib.util.module_from_spec(_codec_spec);_codec_spec.loader.exec_module(_codec)
OLD=_codec.OLD
NEW=_codec.NEW
KEYS=['lumen.health.meals.v1','lumen.health.workouts.v1']

def sample(path,h,sink,persist):
    sink.update(knownPath=str(path),keys={})
    try:
        sink['pathExists']=os.path.lexists(path)
        if sink['pathExists']:
            sink['identityBefore']=h.identity(path)
            raw=h.read(path,256*1024)
            sink.update(plistBytes=len(raw),plistSHA256=h.sha(raw))
            sink['identityAfter']=h.identity(path)
            values=plistlib.loads(raw)
        else:values={}
        sink['healthConnected']=values.get('lumen.health.connected')
        for key in KEYS:
            value=values.get(key);row={'present':key in values,'type':type(value).__name__};sink['keys'][key]=row
            if type(value) is str:
                value = _codec.encode(value)
                row['bytes']=len(value)
                if len(value)<=4096:
                    row['sha256']=h.sha(value)
                    if value==OLD:row['base64']=base64.b64encode(value).decode()
                else:row['oversize']=True
        persist()  # Actual path/hash/both known facts before assertions.
        if sink['pathExists']:
            assert sink['identityBefore']==sink['identityAfter'],'Preference file changed during this snapshot'
            assert stat.S_ISREG(sink['identityBefore']['st_mode'])
        assert sink['healthConnected'] is None or sink['healthConnected'] is False
        for key in KEYS:
            value=values.get(key)
            assert key not in values or (type(value) is str and _codec.encode(value)==OLD),key
        ready=all(type(values.get(key)) is str and _codec.encode(values[key])==OLD for key in KEYS)
        sink['classification']='both-old' if ready else 'initial-missing'
        return ready
    except BaseException:
        sink['error']=traceback.format_exc();persist();raise
    finally:persist()

def wait(path,h,sink,persist,context,clock=time.monotonic,sleep=time.sleep):
    start=clock();sink.update(scope='initial-only actual UI checkpoint; missing or exact original String only',budgetSeconds=10,
        intervalSeconds=0.1,stableSamples=3,stableSpanSeconds=0.2,samples=[])
    streak=[]
    while True:
        row={'elapsed':clock()-start,'context':{},'fixed':{}};sink['samples'].append(row);persist()
        try:
            context(row['context']);persist()
            ready=sample(path,h,row['fixed'],persist)
            now=clock();row['completedElapsed']=now-start
            streak=streak+[now] if ready else []
            persist()
            assert now-start<10,'Finite initial bootstrap deadline'
            if len(streak)>=3 and now-streak[0]>=0.2:
                sink.update(status='PASS bounded initial exact-old presence',acceptedElapsed=now-start);persist();return
            sleep(min(0.1,max(0,10-(clock()-start))))
        except BaseException:
            row['error']=traceback.format_exc();sink['status']='FAILED initial bootstrap';persist();raise
