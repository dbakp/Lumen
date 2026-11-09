"""Bounded nofollow runner transport; exclusive atomic acknowledgement publication."""
import base64
import ctypes
import copy
import errno
import hashlib
import os
from pathlib import Path
import stat
import time
import traceback
import uuid

FIELDS=('st_dev','st_ino','st_mode','st_nlink','st_size','st_mtime_ns','st_ctime_ns')

def facts(value):return {k:getattr(value,k) for k in FIELDS}
def blob(value):return {'bytes':len(value),'sha256':hashlib.sha256(value).hexdigest(),'base64':base64.b64encode(value).decode()}

def _anchors(root):
    path=Path(root);assert path.is_absolute() and '..' not in path.parts
    opened=[];links=[]
    try:
        opened.append(os.open('/',os.O_RDONLY|os.O_DIRECTORY|os.O_CLOEXEC))
        for part in path.parts[1:]:
            parent=opened[-1];child=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC,dir_fd=parent)
            opened.append(child);links.append((parent,part,child))
        return opened,links
    except BaseException:
        for fd in reversed(opened):os.close(fd)
        raise

def _finish(opened,links,result):
    try:
        for parent,name,fd in links:
            a=os.fstat(fd);b=os.stat(name,dir_fd=parent,follow_symlinks=False)
            assert (a.st_dev,a.st_ino,a.st_mode)==(b.st_dev,b.st_ino,b.st_mode),'Ancestor path changed'
    except BaseException:result['errors'].append({'stage':'anchor-finalization','error':traceback.format_exc()})
    finally:
        for fd in reversed(opened):
            try:os.close(fd)
            except BaseException:result['errors'].append({'stage':'descriptor-close','error':traceback.format_exc()})

def _name(value):assert type(value) is str and value not in ('','.','..') and '/' not in value and '\x00' not in value

def read(root,name,limit=8192):
    _name(name);assert type(limit) is int and 0<limit<=1024**2
    result={'file':str(Path(root)/name),'startedAt':time.time(),'status':'FAILED read','errors':[]}
    opened=[];links=[];fd=None;data=bytearray();absent=False
    try:
        opened,links=_anchors(root);parent=opened[-1]
        try:fd=os.open(name,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK|os.O_CLOEXEC,dir_fd=parent)
        except FileNotFoundError:absent=True
        if fd is not None:
            before=os.fstat(fd);result['identityBefore']=facts(before)
            assert stat.S_ISREG(before.st_mode) and before.st_nlink==1 and 0<=before.st_size<=limit
            while len(data)<=limit:
                chunk=os.read(fd,min(64*1024,limit+1-len(data)))
                if not chunk:break
                data.extend(chunk)
            result['raw']=blob(bytes(data));after=os.fstat(fd);named=os.stat(name,dir_fd=parent,follow_symlinks=False)
            result['identityAfter']=facts(after);result['identityNamedAfter']=facts(named)
            assert len(data)==before.st_size and facts(before)==facts(after)==facts(named),'Transport file changed during read'
    except BaseException:result['errors'].append({'stage':'read','error':traceback.format_exc()})
    finally:
        if fd is not None:
            if 'raw' not in result:result['raw']=blob(bytes(data))
            try:os.close(fd)
            except BaseException:result['errors'].append({'stage':'file-close','error':traceback.format_exc()})
        _finish(opened,links,result)
    if not result['errors']:result['status']='ABSENT anchored leaf' if absent else 'SUPPORTED stable transport file'
    result['finishedAt']=time.time();return result

def list_names(root,prefix,max_scanned=2048,max_matched=32):
    assert type(prefix) is str and prefix and '/' not in prefix
    assert type(max_scanned) is int and 0<max_scanned<=4096
    assert type(max_matched) is int and 0<max_matched<=64
    result={'root':str(root),'prefix':prefix,'startedAt':time.time(),'status':'FAILED inventory','names':[],'scannedAtLeast':0,'overflow':False,'errors':[]}
    opened=[];links=[]
    try:
        opened,links=_anchors(root)
        with os.scandir(opened[-1]) as entries:
            for entry in entries:
                result['scannedAtLeast']+=1
                if entry.name.startswith(prefix):result['names'].append(entry.name)
                if result['scannedAtLeast']>max_scanned or len(result['names'])>max_matched:
                    result['overflow']=True;break
        result['names'].sort();assert not result['overflow'],'Bounded transport inventory exceeded'
    except BaseException:result['errors'].append({'stage':'inventory','error':traceback.format_exc()})
    finally:_finish(opened,links,result)
    if not result['errors']:result['status']='SUPPORTED bounded transport names'
    result['finishedAt']=time.time();return result

def write_once(root,name,data,retain_intention):
    """Snapshot must already be durable before caller publishes a valid ack.

    Any post-publication failure is retained as possibly observed by native;
    it cannot truthfully promise that Recover remained blocked.
    """
    _name(name);assert type(data) is bytes and 0<len(data)<=8192 and callable(retain_intention)
    result={'file':str(Path(root)/name),'status':'FAILED publication','startedAt':time.time(),
            'raw':blob(data),'published':False,'mayHaveBeenObserved':False,'errors':[]}
    opened=[];links=[];fd=None
    temporary=name+'.'+str(uuid.uuid4()).lower()+'.tmp';result['temporaryFile']=str(Path(root)/temporary)
    try:
        retain_intention(copy.deepcopy(result))  # Caller must durably retain this before any transport write.
        result['intentionCallbackCompleted']=True
        opened,links=_anchors(root);parent=opened[-1]
        fd=os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW|os.O_CLOEXEC,0o600,dir_fd=parent)
        written=0
        while written<len(data):
            amount=os.write(fd,data[written:]);assert amount>0;written+=amount
        os.fsync(fd);os.close(fd);fd=None;result['temporaryFsynced']=True
        # Darwin SDK sys/stdio.h declares RENAME_EXCL=0x4 and renameatx_np.
        # Unlike Path.replace, this cannot overwrite an earlier/stale ack.
        function=ctypes.CDLL(None,use_errno=True).renameatx_np
        function.argtypes=[ctypes.c_int,ctypes.c_char_p,ctypes.c_int,ctypes.c_char_p,ctypes.c_uint]
        function.restype=ctypes.c_int
        result['publicationStartedAt']=time.time()
        code=function(parent,os.fsencode(temporary),parent,os.fsencode(name),0x4)
        if code!=0:raise OSError(ctypes.get_errno(),os.strerror(ctypes.get_errno()))
        result['published']=True;result['mayHaveBeenObserved']=True
        os.fsync(parent);result['directoryFsynced']=True
        result['publicationObservedAt']=time.time()
    except BaseException:result['errors'].append({'stage':'publication','error':traceback.format_exc()})
    finally:
        if fd is not None:
            try:os.close(fd)
            except BaseException:result['errors'].append({'stage':'file-close','error':traceback.format_exc()})
        _finish(opened,links,result)
    # Independently reopen by its current complete pathname, even after publication errors.
    result['temporaryReadback']=read(root,temporary)
    result['readback']=read(root,name)
    if result['published']:
        if result['readback']['status']!='SUPPORTED stable transport file' or result['readback'].get('raw')!=blob(data):
            result['errors'].append({'stage':'readback','error':'Published bytes/current path mismatch'})
    if not result['errors'] and result['published']:result['status']='SUPPORTED exclusive durable publication'
    result['finishedAt']=time.time();return result
