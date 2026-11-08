"""Three bounded metadata relay generations and one late gate response."""
import base64,json,os,time,traceback
from pathlib import Path

def atomic(path,data,previous,h):
    path=Path(path)
    if previous is None:assert not os.path.lexists(path)
    else:assert h.read(path,16384)==previous
    temporary=path.with_suffix('.'+str(os.getpid())+'.tmp')
    fd=os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW|os.O_CLOEXEC,0o600)
    try:assert os.write(fd,data)==len(data);os.fsync(fd)
    finally:os.close(fd)
    if previous is None:assert not os.path.lexists(path)
    else:assert h.read(path,16384)==previous
    began=time.time();temporary.replace(path)
    assert h.read(path,16384)==data
    return began,time.time()

def publish(path,value,window,persist,h):
    rows=window.setdefault('relays',[]);index=len(rows)
    assert index<3 and value['phase']==['armed','late-ack','checked'][index]
    assert value['targetPhase']==['host-ready','host-late-ack','host-checked'][index]
    base={'runID','pid','sessionID','captureID','nonce','appearanceID','domains','legacyDomains','omitPhotos','taskGeneration'}
    extra={'phase','targetPhase'}|({'ackSHA256'} if index else set())|({'checkRequestID','checkOrdinal'} if index==2 else set())
    assert set(value)==base|extra and all(type(v) is str for v in value.values())
    if index:
        assert {k:value[k] for k in base}=={k:rows[0]['value'][k] for k in base}
        assert len(value['ackSHA256'])==64 and all(c in '0123456789abcdef' for c in value['ackSHA256'])
    if index==2:
        from uuid import UUID
        assert str(UUID(value['checkRequestID'])).upper()==value['checkRequestID'] and value['checkOrdinal']=='1'
        assert value['ackSHA256']==rows[1]['value']['ackSHA256']
    assert Path(path).name=='Lumen-confirmation-lifecycle-relay-'+value['runID'].lower()+'.json'
    previous=base64.b64decode(rows[-1]['raw']['base64'],validate=True) if index else None
    if index:assert str(path)==rows[-1]['file']
    data=json.dumps(value,sort_keys=True,separators=(',',':')).encode();assert 0<len(data)<=4096
    row={'file':str(path),'value':value,'raw':h.row(data),'status':'INTENDED metadata-only relay','started':time.time()}
    rows.append(row);persist()
    try:
        began,observed=atomic(path,data,previous,h)
        row.update(status='PUBLISHED metadata-only relay',publicationStartedAt=began,publicationObservedAt=observed,identity=h.identity(path));persist()
    except BaseException:
        row.update(status='FAILED relay publication; no permission',error=traceback.format_exc());persist();raise
    return row

def publish_ack(path,value,window,persist,h):
    assert not window.get('acknowledged') and not os.path.lexists(path)
    assert set(value)=={'runID','pid','sessionID','captureID','nonce','phase'} and value['phase']=='ui-observed'
    assert all(type(v) is str for v in value.values())
    assert Path(path).name=='Lumen-confirmation-window-'+value['runID'].lower()+'-'+value['nonce'].lower()+'-ack.json'
    data=json.dumps(value,sort_keys=True,separators=(',',':')).encode()
    window.update(ackIntended={'file':str(path),'value':value,'raw':h.row(data),'started':time.time()});persist()
    try:
        began,observed=atomic(path,data,None,h)
        window.update(acknowledged=True,ackAt=began,ackPublishedObservedAt=observed,ackBytes=h.row(data),ackIdentity=h.identity(path));persist()
    except BaseException:
        window['ackError']=traceback.format_exc();persist();raise
