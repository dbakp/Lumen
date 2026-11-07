"""Actual Files ordinary merge twice, with independent current-data and photo audits."""
import argparse, base64, gzip, hashlib, json, os, stat, subprocess, time, traceback
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--case', choices=['legacy', 'encrypted', 'readable'], required=True)
a = p.parse_args()
b = Path(__file__).resolve().parent
repo = b.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
stem = 'HealthHealthyMerge' + a.case.title() + 'R1'
prefix = 'health-healthy-merge-' + a.case + '-r1'
source_name = 'durable-source-r170.json'
source = json.loads((b/source_name).read_bytes())
build = json.loads((b/'health-healthy-merge-r1-build.json').read_bytes())
sha = lambda data: hashlib.sha256(data).hexdigest()
result = raw/(stem+'.xcresult')
assert not result.exists()

def container(kind):
    return Path(subprocess.check_output(['xcrun','simctl','get_app_container',device,'com.dbakp.lumen',kind],text=True).strip())

def identity():
    for name,row in {**source['files'],**source['fixtureInputs']}.items():
        data=(repo/name).read_bytes()
        assert len(data)==row['bytes'] and sha(data)==row['sha256'], name
    assert build['source']==source_name and sha((container('app')/'Lumen').read_bytes())==build['sha256']

def snapshot(root):
    assert root.is_dir() and not root.is_symlink()
    rows={}
    for folder,dirs,files in os.walk(root,followlinks=False):
        for name in dirs: assert not (Path(folder)/name).is_symlink()
        for name in files:
            f=Path(folder)/name;s=f.lstat();assert stat.S_ISREG(s.st_mode) and s.st_size<256*1024
            data=f.read_bytes();rows[str(f.relative_to(root))]={'bytes':len(data),'sha256':sha(data),'base64':base64.b64encode(data).decode()}
    return rows

def decoded(rows,name):
    return json.loads(base64.b64decode(rows[name]['base64']))

inputs=json.loads((b/'health-file-multi-r1-inputs.json').read_bytes())
expected=json.loads((b/'health-file-multi-r1-input-manifest.json').read_bytes())
def provider():
    for row in inputs['files']:
        f=Path(row['seeded']);s=f.lstat()
        assert stat.S_ISREG(s.st_mode) and (s.st_dev,s.st_ino,s.st_mode,s.st_mtime_ns)==(row['device'],row['inode'],row['mode'],row['modifiedNS'])
        assert sha(f.read_bytes())==row['sha256']

def audit(rows,baseline):
    for domain in ['water','meals','workouts']:
        merged={x['id']:x for x in expected['expectedRecords'][domain]}
        merged.update({x['id']:x for x in decoded(baseline,domain+'.json')})
        actual=decoded(rows,domain+'.json')
        assert len(actual)==len(merged)==len({x['id'] for x in actual}),domain
        actual={x['id']:dict(x) for x in actual}
        for key,wanted in merged.items():
            wanted=dict(wanted);observed=actual[key]
            if domain=='meals':
                wanted.pop('photoID',None);observed.pop('photoID',None)
            assert observed==wanted,(domain,key,observed,wanted)
    for name in ['goals.json','profile.json']:
        assert decoded(rows,name)==decoded(baseline,name),name
    old=decoded(baseline,'health-write-intent.json');new=decoded(rows,'health-write-intent.json')
    assert old['owner']==new['owner'] and new['lifecycle']!=old['lifecycle']
    assert new['events']==old['events']==[]
    meals=decoded(rows,'meals.json');photo_ids={x.get('photoID') for x in meals if x['id'].startswith('synthetic-multi-')}
    photo_names={name for name in rows if name.startswith('photos/')}
    if a.case=='readable':
        assert photo_ids=={None} and not photo_names
    else:
        assert len(photo_ids)==1 and None not in photo_ids
        photo_id=next(iter(photo_ids));assert photo_names=={'photos/'+photo_id+'.jpg'}
        assert rows[next(iter(photo_names))]['sha256']==expected['photoSHA256']
    assert not any(name.startswith(('.health-recovery/','.health-recovery-history/')) for name in rows)

def owner_at_preview():
    rows=[]
    for folder in (container('data')/'tmp').glob('LumenBackupWork-v1-*'):
        marker=folder/'.lumen-workspace-owner.json'
        assert folder.is_dir() and not folder.is_symlink() and marker.is_file() and not marker.is_symlink()
        owner=json.loads(marker.read_bytes());assert folder.name=='LumenBackupWork-v1-'+str(owner['pid'])+'-'+owner['id']
        assert Path(subprocess.check_output(['ps','-p',str(owner['pid']),'-o','comm='],text=True).strip())==container('app')/'Lumen'
        rows.append({'path':str(folder),'owner':owner})
    assert rows
    return rows

def cleanup_check(owners):
    pid=owners[0]['owner']['pid'];paths={x['path'] for x in owners}
    paths.update(str(p) for p in (container('data')/'tmp').glob('LumenBackupWork-v1-'+str(pid)+'-*'))
    until=time.monotonic()+2
    while any(Path(p).exists() for p in paths) and time.monotonic()<until:time.sleep(.1)
    assert not any(Path(p).exists() for p in paths),paths
    scan=subprocess.run(['lsof','-nP','-a','-p',str(pid),'-Fn'],capture_output=True,text=True);assert scan.returncode==0
    assert not any(line.startswith('n') and any(line[1:]==p or line[1:].startswith(p+'/') for p in paths) for line in scan.stdout.splitlines())
    return {'pid':pid,'pathsAbsent':sorted(paths),'lsofSHA256':sha(scan.stdout.encode()),'beforeAppTermination':True}

command=['xcodebuild','-project','Lumen.xcodeproj','-scheme','Lumen','-configuration','Debug','-destination','platform=iOS Simulator,id='+device,'-derivedDataPath','/tmp/LumenBatch37Simulator','-clonedSourcePackagesDirPath','/tmp/LumenBatch37Packages','-disableAutomaticPackageResolution','-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-only-testing:LumenUITests/LumenSmokeTests/testHealthBackupHealthyMerge'+a.case.title(),'-resultBundlePath',str(result),'test-without-building']
before=None;first=None;repeat=None;owners=[];cleanup=None;failure=None;started=time.time()
provider()
with (raw/(stem+'.log')).open('xb') as out:
    process=subprocess.Popen(command,cwd=repo,stdout=out,stderr=subprocess.STDOUT)
    subprocess.Popen(['caffeinate','-d','-i','-w',str(process.pid)])
    print('Running',stem,'PID',process.pid,flush=True)
    try:
        deadline=time.monotonic()+600
        while process.poll() is None:
            assert time.monotonic()<deadline,'Native deadline exceeded'
            log=(raw/(stem+'.log')).read_text(errors='replace');tag='health-merge-'+a.case+'-'
            if tag+'first-preview' in log and before is None:
                identity();provider();root=container('group.com.dbakp.lumen')/'LumenData';before=snapshot(root)
                assert len(decoded(before,'water.json'))==1 and decoded(before,'water.json')[0]['ml']==137
                assert decoded(before,'workouts.json')[0]['title']=='Current edited workout'
                assert decoded(before,'goals.json')['stepGoal']==10000
                owners=owner_at_preview()
            if tag+'first-complete' in log and first is None:
                assert before is not None;first=snapshot(root);audit(first,before);provider()
            if tag+'repeat-complete' in log and repeat is None:
                assert first is not None;repeat=snapshot(root);audit(repeat,before);provider()
                for name in ['water.json','meals.json','workouts.json','goals.json','profile.json']:
                    assert decoded(repeat,name)==decoded(first,name),name
                assert {n:r for n,r in repeat.items() if n.startswith('photos/')}=={n:r for n,r in first.items() if n.startswith('photos/')}
                cleanup=cleanup_check(owners)
            time.sleep(.2)
    except BaseException:
        failure=traceback.format_exc();print(failure,flush=True);process.terminate()
    try: code=process.wait(timeout=30)
    except subprocess.TimeoutExpired:process.kill();code=process.wait()
data=(raw/(stem+'.log')).read_bytes();(b/(stem+'.log.gz')).write_bytes(gzip.compress(data,mtime=0))
summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)],text=True));(raw/(stem+'-summary.json')).write_text(json.dumps(summary,indent=2)+'\n')
for ext,pattern in [('PNG','*.png'),('JSON','*.json')]:
    subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(result),'--output-path',str(raw/(stem+ext)),'--filter',pattern],check=True,stdout=subprocess.DEVNULL)
retain=['python3',str(b/'retain-health-record-attachments.py'),'--stem',stem,'--prefix',prefix,'--source',source_name,'--png-dir',str(raw/(stem+'PNG')),'--json-dir',str(raw/(stem+'JSON'))]
if failure or code:retain.append('--include-failed-trial')
subprocess.run(retain,check=True)
after=snapshot(container('group.com.dbakp.lumen')/'LumenData')
outcome={'status':'FAILED' if failure or code else 'Native completed; independent final audit pending','source':source_name,'build':'health-healthy-merge-r1-build.json','case':a.case,'before':before,'first':first,'repeat':repeat,'afterRelaunch':after,'ownersAtPreview':owners,'cleanupBeforeRelaunch':cleanup,'failure':failure,'exitCode':code,'summary':summary,'driverSHA256':sha(Path(__file__).read_bytes()),'checkedAt':time.time()}
target=b/(prefix+'-host-audit.json');target.write_text(json.dumps(outcome,indent=2)+'\n')
assert failure is None and code==0 and summary['passedTests']==1 and summary['failedTests']==summary['skippedTests']==0
assert before and first and repeat and cleanup
identity();provider();audit(after,before)
for name in ['water.json','meals.json','workouts.json','goals.json','profile.json']:assert decoded(after,name)==decoded(repeat,name),name
assert {n:r for n,r in after.items() if n.startswith('photos/')}=={n:r for n,r in repeat.items() if n.startswith('photos/')}
outcome.update(status='PASS ordinary healthy merge/current conflicts/repeat records+photos/relaunch/provider/live cleanup',scope='Main/defaultlight, preferences off only; all original broader contracts remain.')
target.write_text(json.dumps(outcome,indent=2)+'\n');print(outcome['status'],flush=True)
