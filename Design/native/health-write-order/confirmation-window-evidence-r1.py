"""Pure confirmation gate validation plus bounded, nofollow synthetic marker reads."""
import json,math,os,stat
from pathlib import Path
from uuid import UUID
FIELDS={'runID','pid','sessionID','captureID','nonce','appearanceID','domains','legacyDomains','omitPhotos'}
BODY='Selected data will be replaced by records from this file. The older saved data will stay in a private recovery copy on this iPhone.'
def regular(path,limit=16384):
 fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK|os.O_CLOEXEC)
 try:
  facts=os.fstat(fd);assert stat.S_ISREG(facts.st_mode) and facts.st_nlink==1 and 0<facts.st_size<=limit
  data=os.read(fd,limit+1);assert len(data)==facts.st_size
  return data
 finally:os.close(fd)
def uuid(value):
 assert type(value) is str and str(UUID(value)).upper()==value
 return value

def rectangle(r):
 assert set(r)=={'x','y','width','height'} and all(type(v) in (int,float) and math.isfinite(v) for v in r.values())
 assert r['width']>0 and r['height']>0
 return r

def contains(outer,inner):
 rectangle(outer);rectangle(inner)
 return inner['x']>=outer['x'] and inner['y']>=outer['y'] and inner['x']+inner['width']<=outer['x']+outer['width']+.001 and inner['y']+inner['height']<=outer['y']+outer['height']+.001

def validate(gate,native,marker,started,now):
 assert set(gate)==FIELDS and all(type(v) is str for v in gate.values())
 for key in ['runID','sessionID','captureID','nonce','appearanceID']:uuid(gate[key])
 assert gate['pid'].isdigit() and str(int(gate['pid']))==gate['pid'] and int(gate['pid'])>0
 assert gate['domains']==gate['legacyDomains']=='meals' and gate['omitPhotos']=='false'
 assert native['status']=='ready' and native['sequence']==3 and native['knownKeyWritten'] is False and native['singleUseConsumed'] is False
 assert all(gate[k]==str(native[k]) for k in ['runID','pid','sessionID','captureID'])
 assert marker['gate']==dict(gate,phase='armed',targetPhase='host-ready')
 assert marker['scope']=='actual-legacy-target-change-during-confirmation' and marker['title']=='Replace selected data?' and marker['body']==BODY
 assert type(marker['at']) in (int,float) and math.isfinite(marker['at']) and started<=marker['at']<=now
 assert marker['attachmentName']=='health-legacy-target-change-confirmation-before-mutation'
 assert type(marker['imageBytes']) is int and 1000<marker['imageBytes']<=4*1024*1024
 assert type(marker['imageSHA256']) is str and len(marker['imageSHA256'])==64 and all(c in '0123456789abcdef' for c in marker['imageSHA256'])
 assert contains(marker['appFrame'],marker['alertFrame'])
 assert all(contains(marker['alertFrame'],marker[k]) for k in ['bodyFrame','recoverFrame','cancelFrame'])
 assert all(marker[k]['height']>=44 and marker[k]['width']>=44 for k in ['recoverFrame','cancelFrame'])
 assert marker['recoverFrame']!=marker['cancelFrame']
 return {k:gate[k] for k in ['runID','pid','sessionID','captureID','nonce']}|{'phase':'ui-observed'}
