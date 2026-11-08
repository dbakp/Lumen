"""Remove only completed219 host scratch after exact retained logic/source backup.
No app build, simulator mutation, unrelated cache or raw-video deletion.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import stat
import subprocess
import time

p=argparse.ArgumentParser();p.add_argument('--proof',required=True);a=p.parse_args()
repo=Path('/Users/davidbakposada/Documents/ChatGPT/Lumen');base=repo/'Design/native/health-write-order'
proof=json.loads(Path(a.proof).read_text());assert proof['publisherExit']==0
remote=subprocess.check_output(['git','rev-parse','origin/main'],cwd=repo,text=True).strip();assert proof['commit']==remote
bound={row['file']:row for row in proof['proof']}
required=['durable-source-r219.json','durable-source-r219.json.gz','source219-logic-r1-outcome.json','source219-logic-build-r1.log.gz','source219-logic-review-r1.log.gz','source219-logic-full-r1.log.gz','source219-origin-review-r1.json','source219-origin-review-r1-fixtures.json.gz','health-legacy-capture-state-source219-round2-part88-failed-native.json','source219-capture-state-pending-back-r1-root-review-final.json','source219-completed-host-cache-cleanup-r1-executed.py']
assert all(str((base/name).relative_to(repo)) in bound for name in required)
for name,row in bound.items():
    path=repo/name;assert path.is_file() and not path.is_symlink();data=path.read_bytes()
    assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'],name
    assert subprocess.check_output(['git','show','origin/main:'+name],cwd=repo)==data,name
logic=json.loads((base/'source219-logic-r1-outcome.json').read_text());assert logic['fullComponents']['total']==2350 and logic['focusedReviewChecks']==23 and all(row['exitCode']==0 for row in logic['runs'])
review=json.loads((base/'source219-capture-state-pending-back-r1-root-review-final.json').read_text());assert review['independentFullRead'] is True and review['sourceArchiveInputsExact']==318
cache=Path('/tmp/LumenLogicBuild');assert cache.is_dir() and not cache.is_symlink() and cache.resolve()==Path('/private/tmp/LumenLogicBuild')
binary=Path(logic['binary']['path']);assert binary.is_relative_to(cache);assert binary.stat().st_size==logic['binary']['bytes'] and hashlib.sha256(binary.read_bytes()).hexdigest()==logic['binary']['sha256']
scan=subprocess.run(['lsof','-nP','+D',str(cache)],capture_output=True,text=True);assert scan.returncode==1 and not scan.stdout.strip() and not scan.stderr.strip(), 'Host scratch open or absence unverified'
processes=subprocess.run(['ps','-axo','pid=,command='],capture_output=True,text=True,check=True)
assert not any('/tmp/LumenLogicBuild' in line or '/private/tmp/LumenLogicBuild' in line for line in processes.stdout.splitlines()),'Host scratch process still present'
video=Path(review['unbackedRawVideo']['file']);assert video.is_file() and not video.is_symlink() and video.stat().st_size==387905024
allocated=logical=regular=symlinks=directories=0;seen=set()
for parent,dirs,files in os.walk(cache,followlinks=False):
    directories+=1
    for name in dirs+files:
        path=Path(parent)/name;facts=path.lstat()
        if stat.S_ISLNK(facts.st_mode):symlinks+=1;continue
        if stat.S_ISREG(facts.st_mode):
            regular+=1;logical+=facts.st_size
            identity=(facts.st_dev,facts.st_ino)
            if identity not in seen:allocated+=facts.st_blocks*512;seen.add(identity)
before=shutil.disk_usage(repo).free
shutil.rmtree(cache) # Python's fd-based rmtree unlinks symlinks, never their targets.
assert not os.path.lexists(cache) and video.is_file() and video.stat().st_size==387905024
time.sleep(1)
after=shutil.disk_usage(repo).free;observed=after-before;credit=max(0,min(allocated,observed))
out={'status':'Completed219hostscratch removed after exact source/logic/root/critic remoteproofs; no app rebuild or simulator/rawvideo deletion','commit':remote,'verifiedPaths':len(bound),'removed':[str(cache)],'regularFiles':regular,'directories':directories,'symlinksUnlinkedNotFollowed':symlinks,'logicalBytes':logical,'uniqueRegularAllocatedBytes':allocated,'freeBefore':before,'freeAfter':after,'observedFreeChange':observed,'creditedRecoveredBytes':credit,'previousAggregateCreditBytes':8917261911,'aggregateCreditedBytes':8917261911+credit,'retained':'Native/package cache for immediate220reuse; repository/canonicalevidence/currentinputs/suppliedskill; rawunbacked219video387905024 and earlier191video untouched','checkedAt':time.time(),'physicalDeviceActions':False}
(base/'source219-completed-host-cache-cleanup-r1.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out),flush=True)
