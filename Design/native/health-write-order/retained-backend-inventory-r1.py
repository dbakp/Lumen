"""Read only names/metadata of the dedicated root's task-owned sibling namespace."""
import os
from pathlib import Path
import stat
import time


def inventory(parent):
    result={'status':'FAILED namespace inventory','path':str(parent),'startedAt':time.time(),'entries':{},'errors':[]}
    opened=[];links=[]
    try:
        path=Path(parent)
        assert path.is_absolute() and '..' not in path.parts
        opened.append(os.open('/',os.O_RDONLY|os.O_DIRECTORY|os.O_CLOEXEC))
        for part in path.parts[1:]:
            previous=opened[-1];fd=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC,dir_fd=previous)
            opened.append(fd);links.append((previous,part,fd))
        root=opened[-1]
        def names():return sorted(name for name in os.listdir(root) if name.startswith('LumenData'))
        before=names();result['namesBefore']=before
        assert len(before)<=32,'Bounded namespace inventory exceeded'
        for name in before:
            try:
                value=os.stat(name,dir_fd=root,follow_symlinks=False)
                result['entries'][name]={'st_dev':value.st_dev,'st_ino':value.st_ino,'st_mode':value.st_mode,
                    'st_nlink':value.st_nlink,'st_size':value.st_size,'st_mtime_ns':value.st_mtime_ns,'st_ctime_ns':value.st_ctime_ns}
                assert stat.S_ISDIR(value.st_mode),'Task namespace contains a non-directory entry'
            except BaseException as error:result['errors'].append({'entry':name,'error':str(error)})
        after=names();result['namesAfter']=after;assert before==after,'Task sibling names changed during inventory'
        for previous,name,fd in links:
            a=os.fstat(fd);b=os.stat(name,dir_fd=previous,follow_symlinks=False)
            assert (a.st_dev,a.st_ino,a.st_mode)==(b.st_dev,b.st_ino,b.st_mode),'Ancestor path binding changed'
        assert not result['errors'];result['status']='SUPPORTED bounded task namespace inventory'
    except BaseException as error:result['errors'].append({'stage':'inventory','error':str(error)})
    finally:
        for fd in reversed(opened):os.close(fd)
    result['finishedAt']=time.time();return result
