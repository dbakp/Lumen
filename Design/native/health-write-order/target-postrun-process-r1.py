"""Read-only bound-app process classification; no launches, kills or repairs."""
import hashlib
from pathlib import Path
import subprocess
import time
import traceback


def classify(query, pid, executable):
    assert type(pid) is int and pid>0
    path=Path(executable);assert path.is_absolute() and path.name=='Lumen' and path.parent.name=='Lumen.app'
    assert query['exit']==0 and query['parseComplete'] is True and query['parsedRows']>0
    assert query['stdoutBytes']>0 and not query.get('error')
    matches=query['matches']
    bound=[r for r in matches if r['pid']==pid]
    if any(r['executable']!=executable for r in bound):raise AssertionError('Bound PID identity changed')
    if len(matches)>1:raise AssertionError('Ambiguous or extra matching app processes')
    if not bound and matches:raise AssertionError('Same app relaunched with a different PID')
    if not matches:return 'absent'
    assert matches==[{'pid':pid,'executable':executable}]
    return 'live'


def observe(pid, executable, sink, persist, run=subprocess.run):
    sink.update(command=['/bin/ps','-axo','pid=,comm='],expectedPID=pid,expectedExecutable=executable,
        startedAt=time.time(),status='FAILED or incomplete process observation',matches=[])
    persist()
    try:
        result=run(sink['command'],capture_output=True,timeout=10)
        raw=result.stdout;err=result.stderr
        assert type(raw) is bytes and type(err) is bytes
        sink.update(exit=result.returncode,stdoutBytes=len(raw),stdoutSHA256=hashlib.sha256(raw).hexdigest(),
            stderrBytes=len(err),stderrSHA256=hashlib.sha256(err).hexdigest(),stderr=err[:16384].decode('utf-8',errors='replace'))
        persist()
        assert result.returncode==0 and 0<len(raw)<=8*1024*1024 and len(err)<=16384
        lines=raw.decode('utf-8').splitlines();seen=set();parsed=0
        for ordinal,line in enumerate(lines):
            if not line.strip():continue
            parts=line.strip().split(None,1)
            if len(parts)!=2 or not parts[0].isdigit() or int(parts[0]) in seen:
                sink['invalidRow']={'ordinal':ordinal,'bytes':len(line.encode()),'sha256':hashlib.sha256(line.encode()).hexdigest()}
                persist();raise AssertionError('Malformed or duplicate process enumeration row')
            actual=int(parts[0]);seen.add(actual);parsed+=1
            if actual==pid or parts[1]==executable:sink['matches'].append({'pid':actual,'executable':parts[1]})
        sink.update(parsedRows=parsed,parseComplete=True);persist()
        mode=classify(sink,pid,executable)
        sink.update(mode=mode,status='PASS explicit '+mode+' process classification',finishedAt=time.time());persist();return mode
    except BaseException:
        sink.update(status='FAILED process observation',error=traceback.format_exc(),finishedAt=time.time());persist();raise


def audit(pid, executable, sink, persist, collect, live_paths, *, run=subprocess.run,
          clock=time.monotonic, sleep=time.sleep):
    """Two sampled endpoint classifications; never turn a query error into absence."""
    sink.update(status='FAILED or incomplete final endpoint audit',samples=[],minimumGapSeconds=0.25)
    modes=[];persist()
    try:
        for ordinal in range(2):
            if ordinal:sleep(0.25)
            row={'startedAt':time.time(),'monotonic':clock(),'process':{}};sink['samples'].append(row);persist()
            mode=observe(pid,executable,row['process'],persist,run=run);modes.append(mode)
            collect(row,mode);persist()
            if mode=='live':
                row['liveOpenPaths']={};live_paths(row['liveOpenPaths']);persist()
            else:row['openPathScope']='No matching bound-app process at this sample; not a live-app lsof result or global descriptor claim'
            row['finishedAt']=time.time();row['completedMonotonic']=clock();persist()
        assert modes[0]==modes[1],'App process classification changed between endpoints'
        assert sink['samples'][1]['monotonic']-sink['samples'][0]['monotonic']>=0.25
        sink.update(mode=modes[0],status='PASS two sampled '+modes[0]+' app endpoints with mandatory protected-state checks');persist()
    except BaseException:
        sink.update(status='FAILED final endpoint audit',error=traceback.format_exc());persist();raise
