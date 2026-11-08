"""Salvage each actual result independently, including failed/partial native trials."""
import gzip,hashlib,json,subprocess,os,stat
from pathlib import Path
sha=lambda data:hashlib.sha256(data).hexdigest()
def retain(base,raw,stem,prefix,source):
    result=raw/(stem+'.xcresult')
    outcome={'summary':None,'summaryAvailable':False,'images':[],'readbacks':[],'errors':[],'queries':[]}
    def error(step):
        import traceback
        outcome['errors'].append({'step':step,'error':traceback.format_exc()})
    def query(label,command):
        proc=subprocess.run(command,capture_output=True)
        facts={'label':label,'command':command,'exitCode':proc.returncode}
        for stream,data in [('stdout',proc.stdout),('stderr',proc.stderr)]:
            name=prefix+'-'+label+'-'+stream+'.gz';(base/name).write_bytes(gzip.compress(data,mtime=0))
            facts[stream]={'retained':name,'bytes':len(data),'sha256':sha(data)}
        outcome['queries'].append(facts)
        return proc
    try:
        log=(raw/(stem+'.log')).read_bytes();(base/(stem+'.log.gz')).write_bytes(gzip.compress(log,mtime=0))
        outcome['log']={'retained':stem+'.log.gz','bytes':len(log),'sha256':sha(log)}
    except Exception:error('log retention')
    try:
        proc=query('summary-query',['xcrun','xcresulttool','get','test-results','summary','--path',str(result)])
        if proc.returncode==0:
            summary=json.loads(proc.stdout)
            assert isinstance(summary,dict)
            outcome['summary']=summary;outcome['summaryAvailable']=True
            for path in [raw/(stem+'-summary.json'),base/(prefix+'-summary.json')]:path.write_text(json.dumps(summary,indent=2)+'\n')
        else:outcome['errors'].append({'step':'summary query','exitCode':proc.returncode})
    except Exception:error('summary acquisition/parse')
    for ext,pattern,index in [('PNG','*.png','images'),('JSON','*.json','readbacks')]:
        directory=raw/(stem+ext)
        try:
            proc=query('export-'+ext.lower(),['xcrun','xcresulttool','export','attachments','--path',str(result),'--output-path',str(directory),'--filter',pattern])
            if proc.returncode:outcome['errors'].append({'step':'export '+ext,'exitCode':proc.returncode})
        except Exception:error('export '+ext)
        # A failed exporter/summary does not disqualify any available peer.
        try:
            manifestpath=directory/'manifest.json';assert not manifestpath.is_symlink() and manifestpath.is_file()
            data=manifestpath.read_bytes();name=prefix+'-'+ext.lower()+'-original-manifest.json.gz'
            (base/name).write_bytes(gzip.compress(data,mtime=0))
            outcome[index+'Manifest']={'retained':name,'bytes':len(data),'sha256':sha(data)}
            manifest=json.loads(data)
            for case in manifest:
                for metadata in case['attachments']:
                    try:
                        name=metadata['exportedFileName'];assert Path(name).name==name
                        origin=directory/name;assert origin.is_file() and not origin.is_symlink()
                        data=origin.read_bytes();target=base/(prefix+'-'+name)
                        assert not target.exists() or target.read_bytes()==data
                        target.write_bytes(data)
                        outcome[index].append({'file':target.name,'raw':str(origin),'metadata':metadata,'test':case['testIdentifier'],
                            'source':source,'bytes':len(data),'sha256':sha(data),'individuallyOpened':False})
                    except Exception:error('retain individual '+ext)
        except Exception:error('read available '+ext+' manifest')
        (base/(prefix+'-'+index+'.json')).write_text(json.dumps(outcome[index],indent=2)+'\n')
    outcome['bundleInventory']=[]
    try:
        assert result.is_dir() and not result.is_symlink()
        for parent,dirs,files in os.walk(result,followlinks=False):
            for name in dirs+files:
                path=Path(parent)/name;facts=path.lstat()
                outcome['bundleInventory'].append({'path':str(path.relative_to(result)),
                    'kind':'directory' if stat.S_ISDIR(facts.st_mode) else 'regular' if stat.S_ISREG(facts.st_mode) else 'symlink' if stat.S_ISLNK(facts.st_mode) else 'other',
                    'bytes':facts.st_size,'mode':facts.st_mode,'inode':facts.st_ino,'device':facts.st_dev,'modifiedNS':facts.st_mtime_ns})
    except Exception:error('partial bundle inventory')
    outcome['partialOrFailedArtifactsRemainAt']=str(result)
    return outcome
