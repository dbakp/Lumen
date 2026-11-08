"""Metadata-only test-runner relay; never grants permission to change saved data."""
import base64,json,os,time,traceback
from pathlib import Path

def message(gate,phase,native_sha=None):
 assert phase in ['armed','mutated']
 value=dict(gate,phase=phase,targetPhase='host-ready' if phase=='armed' else 'host-target-changed')
 if phase=='mutated':
  assert type(native_sha) is str and len(native_sha)==64 and all(c in '0123456789abcdef' for c in native_sha)
  value['nativeCheckpointSHA256']=native_sha
 else:assert native_sha is None
 return value

def publish(path,value,window,persist,h):
 """Only two guarded, atomic generations in this unique synthetic run."""
 path=Path(path);rows=window.setdefault('relays',[])
 assert len(rows)<2 and (not rows and value['phase']=='armed' or len(rows)==1 and value['phase']=='mutated')
 assert path.name=='Lumen-confirmation-relay-'+value['runID'].lower()+'.json'
 if rows:
  assert str(path)==rows[-1]['file'] and h.read(path,4096)==base64.b64decode(rows[-1]['raw']['base64'],validate=True)
  previous={k:v for k,v in rows[-1]['value'].items() if k not in ['phase','targetPhase']}
  assert {k:v for k,v in value.items() if k not in ['phase','targetPhase','nativeCheckpointSHA256']}==previous
 else:assert not os.path.lexists(path),'No preexisting relay may be overwritten'
 data=json.dumps(value,sort_keys=True,separators=(',',':')).encode();assert 0<len(data)<=4096
 record={'file':str(path),'value':value,'raw':h.row(data),'status':'INTENDED metadata-only relay','started':time.time()};rows.append(record);persist()
 temporary=path.with_suffix('.'+value['phase']+'.tmp')
 try:
  fd=os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
  try:assert os.write(fd,data)==len(data);os.fsync(fd)
  finally:os.close(fd)
  if len(rows)==1:assert not os.path.lexists(path)
  else:assert h.read(path,4096)==base64.b64decode(rows[-2]['raw']['base64'],validate=True)
  record['publicationStartedAt']=time.time();temporary.replace(path)
  assert h.read(path,4096)==data
  record.update(status='PUBLISHED metadata-only relay',identity=h.identity(path),publicationObservedAt=time.time());persist()
 except BaseException:
  record.update(status='FAILED relay publication; no permission',error=traceback.format_exc(),finished=time.time());persist();raise
 return record
