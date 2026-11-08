"""Salvage actual native peers independently, including failed/partial trials."""
import gzip,hashlib,json,os,stat,subprocess,traceback
from pathlib import Path
sha=lambda data:hashlib.sha256(data).hexdigest()
def retain(base,raw,stem,prefix,source):
    result=raw/(stem+'.xcresult')
    outcome={'summary':None,'summaryAvailable':False,'images':[],'readbacks':[],'errors':[],'queries':[],'bundleInventory':[]}
    def failed(step,error=None):
        outcome['errors'].append({'step':step,'error':str(error) if error is not None else traceback.format_exc()})
    def state():
        try:(base/(prefix+'-retention-state.json')).write_text(json.dumps(outcome,indent=2)+'\n')
        except Exception as error:failed('write incremental retention state',error)
    def write_index(index):
        try:(base/(prefix+'-'+index+'.json')).write_text(json.dumps(outcome[index],indent=2)+'\n')
        except Exception as error:failed('write '+index+' index',error)
        state()
    def archive(label,data):
        name=prefix+'-'+label+'.gz'
        facts={'retained':name,'bytes':len(data),'sha256':sha(data)}
        try:(base/name).write_bytes(gzip.compress(data,mtime=0));facts['retainedExact']=True
        except Exception as error:failed('archive '+label,error);facts['retainedExact']=False
        return facts
    def query(label,command):
        proc=subprocess.run(command,capture_output=True)
        facts={'label':label,'command':command,'exitCode':proc.returncode}
        outcome['queries'].append(facts)
        for stream,data in [('stdout',proc.stdout),('stderr',proc.stderr)]:
            facts[stream]=archive(label+'-'+stream,data);state()
        return proc
    state()
    try:
        log=(raw/(stem+'.log')).read_bytes()
        name=stem+'.log.gz';facts={'retained':name,'bytes':len(log),'sha256':sha(log)}
        outcome['log']=facts
        (base/name).write_bytes(gzip.compress(log,mtime=0));facts['retainedExact']=True
    except Exception:failed('log retention')
    state()
    try:
        proc=query('summary-query',['xcrun','xcresulttool','get','test-results','summary','--path',str(result)])
        if proc.returncode==0:
            summary=json.loads(proc.stdout);assert isinstance(summary,dict)
            outcome['summary']=summary;outcome['summaryAvailable']=True
            for path in [raw/(stem+'-summary.json'),base/(prefix+'-summary.json')]:
                try:path.write_text(json.dumps(summary,indent=2)+'\n')
                except Exception as error:failed('write actual summary '+str(path),error)
        else:failed('summary query','Exit '+str(proc.returncode))
    except Exception:failed('summary acquisition/parse')
    state()
    for ext,pattern,index in [('PNG','*.png','images'),('JSON','*.json','readbacks')]:
        directory=raw/(stem+ext)
        try:
            proc=query('export-'+ext.lower(),['xcrun','xcresulttool','export','attachments','--path',str(result),'--output-path',str(directory),'--filter',pattern])
            if proc.returncode:failed('export '+ext,'Exit '+str(proc.returncode))
        except Exception:failed('export '+ext)
        state();manifest=None
        try:
            manifestpath=directory/'manifest.json';assert not manifestpath.is_symlink() and manifestpath.is_file()
            data=manifestpath.read_bytes()
            outcome[index+'Manifest']=archive(ext.lower()+'-original-manifest.json',data)
            manifest=json.loads(data);assert isinstance(manifest,list)
        except Exception:failed('read available '+ext+' manifest')
        state()
        if manifest is not None:
            for case_number,case in enumerate(manifest):
                try:
                    entries=case['attachments'];test=case['testIdentifier'];assert isinstance(entries,list)
                except Exception:
                    failed('read '+ext+' case '+str(case_number));state();continue
                for entry_number,metadata in enumerate(entries):
                    try:
                        name=metadata['exportedFileName'];assert Path(name).name==name
                        origin=directory/name;assert origin.is_file() and not origin.is_symlink()
                        data=origin.read_bytes();target=base/(prefix+'-'+name)
                        assert not target.exists() or (not target.is_symlink() and target.read_bytes()==data)
                        target.write_bytes(data)
                        outcome[index].append({'file':target.name,'raw':str(origin),'metadata':metadata,'test':test,
                            'source':source,'bytes':len(data),'sha256':sha(data),'individuallyOpened':False})
                    except Exception:failed('retain '+ext+' case '+str(case_number)+' entry '+str(entry_number))
                    write_index(index)
        write_index(index)
    try:
        assert result.is_dir() and not result.is_symlink()
        def walk_error(error):failed('walk partial bundle',error);state()
        for parent,dirs,files in os.walk(result,followlinks=False,onerror=walk_error):
            for name in dirs+files:
                try:
                    path=Path(parent)/name;facts=path.lstat()
                    outcome['bundleInventory'].append({'path':str(path.relative_to(result)),
                        'kind':'directory' if stat.S_ISDIR(facts.st_mode) else 'regular' if stat.S_ISREG(facts.st_mode) else 'symlink' if stat.S_ISLNK(facts.st_mode) else 'other',
                        'bytes':facts.st_size,'mode':facts.st_mode,'inode':facts.st_ino,'device':facts.st_dev,'modifiedNS':facts.st_mtime_ns})
                except Exception:failed('inventory individual partial path')
        state()
    except Exception:failed('partial bundle inventory')
    outcome['partialOrFailedArtifactsRemainAt']=str(result);state()
    return outcome
