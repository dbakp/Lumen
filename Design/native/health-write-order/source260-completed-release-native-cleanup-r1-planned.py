"""Delete only completed backed Source260 Release/raw navigation outputs, after185 exact."""
from pathlib import Path
import hashlib, json, os, shutil, stat, subprocess, time
B=Path(__file__).resolve().parent; R=B.parents[2]
output=B/'source260-completed-release-native-cleanup-r1.json'
assert not output.exists()
proof=json.loads((B/'source260-release-exact-github.json').read_bytes())
assert proof['source']=='durable-source-r260.json'
for ref in ['HEAD','origin/main']:
    assert subprocess.check_output(['git','rev-parse',ref],cwd=R,text=True).strip()==proof['commit']
rows={}
for row in proof['proofs']:
    assert row['file'] not in rows
    rows[row['file']]=row
required=['health-current-release-source260-round2-part185.json','source260-root-part185-review.json',
 'health-current-release-source260-r1-outcome.json','health-current-release-source260-r1-audit.json',
 'source260-root-release-audit-r1.json','source260-release-root-readback-r1.json',
 'source260-unsigned-release-r1-build.log.gz','source260-unsigned-release-r1-settings-audit.json',
 'source260-unsigned-release-r1-swift-filelist.txt.gz','source260-release-generated-assets-r1.swift.txt.gz',
 'health-current-release-source210-r1-auditor.py',Path(__file__).name]
for case,part in [('children',182),('pending-back',183),('sheet-dismiss',184)]:
    prefix='retained-owner-source260-'+case+'-r1'
    driver=json.loads((B/(prefix+'-driver.json')).read_bytes())
    assert driver['nativeExit']==0 and driver['errors']==[] and driver['originalFailures']==[]
    required += [prefix+suffix for suffix in ['-driver.json','-finalization.json','-mandatory-audit.json','-mandatory-checker-query.json','-native.log.gz','-trace.json']]
    required += [row['file'] for row in driver['originals']]
    required += [f'health-retained-review-owner-source260-round2-part{part}-{case if case!="children" else "children"}-native.json',f'source260-root-part{part}-review.json']
verified=[]
for name in dict.fromkeys(required):
    path=B/name; relative=str(path.relative_to(R)); wanted=rows[relative]
    assert not path.is_symlink(); data=path.read_bytes()
    assert len(data)==wanted['bytes'] and hashlib.sha256(data).hexdigest()==wanted['sha256']
    assert subprocess.check_output(['git','cat-file','blob',proof['commit']+':'+relative],cwd=R)==data
    verified.append(relative)
root=json.loads((B/'source260-root-part185-review.json').read_bytes())
assert root['source']=='durable-source-r260.json' and root['scopedStaticAcceptance'] is True
assert root['globalProductAcceptance'] is False
out=json.loads((B/'health-current-release-source260-r1-outcome.json').read_bytes())
assert out['buildExitCode']==out['auditExitCode']==0
raw=Path('/tmp/LumenBatch44Checks')
targets=[Path('/tmp/LumenBatch37Release')]
for stem in ['RetainedOwnerSource260ChildrenR1','RetainedOwnerSource260PendingbackR1','RetainedOwnerSource260SheetdismissR1']:
    targets += [raw/(stem+'.xcresult'),raw/(stem+'All'),raw/(stem+'.log')]
targets += [raw/name for name in ['Source260UnsignedReleaseR1.log','Source260UnsignedReleaseR1Audit.log','Source260UnsignedReleaseR1Settings.json','Source260UnsignedReleaseR1Settings.log']]
assert all(p.exists() and not p.is_symlink() for p in targets)
processes=subprocess.check_output(['ps','-axo','pid=,comm=,args='],text=True)
for line in processes.splitlines():
    parts=line.split(None,2)
    if len(parts)==3 and Path(parts[1]).name in ['xcodebuild','swift','swift-build','swiftc','swift-frontend','xcresulttool']:
        assert not any(str(p) in parts[2] for p in targets),'Relevant build/test/query still active'
entries=symlinks=allocated=0
for target in targets:
    paths=[target]
    if target.is_dir():
        for parent,dirs,files in os.walk(target,followlinks=False):paths += [Path(parent)/n for n in dirs+files]
    for p in paths:
        info=p.lstat();entries+=1;allocated+=info.st_blocks*512;symlinks+=int(stat.S_ISLNK(info.st_mode))
before=shutil.disk_usage(R).free
for target in targets:
    if target.is_dir():shutil.rmtree(target)
    else:target.unlink()
after=shutil.disk_usage(R).free
assert not any(p.exists() for p in targets)
credited=min(allocated,max(0,after-before))
result={'status':'PASS scoped completed Source260 Release/native raw cleanup','source':'durable-source-r260.json',
 'proof':'source260-release-exact-github.json','proofCommit':proof['commit'],'backedRequiredPathsVerified':verified,
 'deleted':[str(p) for p in targets],'entries':entries,'symlinksNotFollowed':symlinks,'allocatedBytes':allocated,
 'availableBeforeBytes':before,'availableAfterBytes':after,'creditedRecoveryBytes':credited,
 'aggregateCreditedRecoveryBytes':17028726359+credited,
 'historicalBoundary':'All Source260 raw/native export/Release/cache/settings/FileList-bound runners are historical after cleanup, never rerun. Canonical receipts/logs/originals remain.',
 'preserved':'Working repository/current inputs/provider/design skill/currentDebug/packages for immediate reuse/unbacked191219videos/other projects/global caches/shared runtimes/simulator and personal data',
 'checkedAt':time.time()}
output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
