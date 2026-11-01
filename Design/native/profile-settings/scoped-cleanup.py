import pathlib, subprocess, os, stat, json, hashlib, gzip, datetime, shutil, sys

repo = pathlib.Path('/Users/davidbakposada/Documents/ChatGPT/Lumen')
evidence = repo / 'Design/native/profile-settings'
device_id = 'A540EFA6-F96F-4038-B53D-FEFADB1A0862'
roots = [pathlib.Path('/tmp') / n for n in ['LumenBatch37Checks', 'LumenBatch37Release', 'LumenBatch37LogicBuild']]
device_root = pathlib.Path('/Users/davidbakposada/Library/Developer/CoreSimulator/Devices') / device_id
env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')

def run(*args): return subprocess.check_output(args, cwd=repo, env=env)
def now(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def available():
    s = os.statvfs(repo)
    return s.f_bavail * s.f_frsize
def devices():
    return {d['udid']:d for group in json.loads(run('xcrun','simctl','list','devices','--json'))['devices'].values() for d in group}

assert len(sys.argv) == 2
head = run('git','rev-parse','HEAD').decode().strip()
assert sys.argv[1] == head
receipt = json.loads((evidence/'publication-readback.json').read_text())
assert receipt['commit'] == head and receipt['githubMainMatches'] and receipt['githubTreeMatches']
assert run('gh','api','repos/dbakp/Lumen/git/ref/heads/main','--jq','.object.sha').decode().strip() == head
for row in receipt['files']:
    p = repo/row['path']
    assert p.is_file() and not p.is_symlink()
    assert hashlib.sha256(p.read_bytes()).hexdigest() == row['sha256'], row['path']
for line in run('ps','-axo','pid=,command=').decode().splitlines():
    if 'LumenBatch37' in line and any(x in line for x in ['xcodebuild ', 'swift-frontend ', 'swiftc ', 'xcresulttool ']):
        raise RuntimeError('Active producer: '+line)
before_devices = devices()
assert before_devices[device_id]['name'] == 'Lumen Batch37 compact verification'
for preserved in ['AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481','520290CC-97B3-4E21-9FD9-E87993733521','F2ACCCB5-E5B3-426F-B962-955A113D4EF4']:
    assert preserved in before_devices
if before_devices[device_id]['state'] != 'Shutdown':
    run('xcrun','simctl','shutdown',device_id)
assert devices()[device_id]['state'] == 'Shutdown'

rows, summaries, seen = [], [], set()
for root in roots + [device_root]:
    assert stat.S_ISDIR(root.lstat().st_mode) and not root.is_symlink(), root
    summary = dict(root=str(root),regularFilePaths=0,symbolicLinks=0,logicalFileBytes=0,uniqueInodeAllocatedBytes=0)
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            p = pathlib.Path(directory)/name
            s = p.lstat()
            row = dict(path=str(p),mode=s.st_mode,device=s.st_dev,inode=s.st_ino,bytes=s.st_size,blocks512=s.st_blocks)
            if stat.S_ISLNK(s.st_mode):
                summary['symbolicLinks'] += 1
                row['linkTargetNotFollowed'] = os.readlink(p)
            elif stat.S_ISREG(s.st_mode):
                summary['regularFilePaths'] += 1
                summary['logicalFileBytes'] += s.st_size
                key = s.st_dev,s.st_ino
                if key not in seen:
                    summary['uniqueInodeAllocatedBytes'] += s.st_blocks*512
                    seen.add(key)
            elif not stat.S_ISDIR(s.st_mode):
                raise RuntimeError('Unexpected disposable entry: '+str(p))
            rows.append(row)
    summaries.append(summary)
inventory = gzip.compress(('\n'.join(json.dumps(r,sort_keys=True) for r in rows)+'\n').encode(),mtime=0)
(evidence/'cleanup-inventory.jsonl.gz').write_bytes(inventory)
ledger = dict(status='inventory complete; deletion starting',applicationCommit=head,verifiedGitBlobs=receipt['checkedFiles'],roots=summaries,inventoryFile='cleanup-inventory.jsonl.gz',inventorySHA256=hashlib.sha256(inventory).hexdigest(),availableBytesBefore=available(),startedUTC=now(),retainedWorkingCaches=['/tmp/LumenBatch37Simulator','/tmp/LumenBatch37Packages'],notes=['No symbolic-link target followed; delete only this batch-created compact simulator through simctl.','Available-volume change is separate from logical/unique-inode accounting and includes APFS/concurrent effects.','Keep one simulator build cache and its pinned dependency checkout for immediate personal-context/consent work. No cleanup-only build.'],preserved=['Working repository, useful originals, compact outcomes/source/logs, current inputs and supplied skill/archive','Canonical research/model/source/environment/dataset/frozen inputs','Primary, Watch, Taskfold and other simulators/shared runtimes; unrelated projects, personal files and global/system/browser/application caches'])
(evidence/'storage-cleanup.json').write_text(json.dumps(ledger,indent=2)+'\n')
for root in roots:
    assert stat.S_ISDIR(root.lstat().st_mode) and not root.is_symlink()
    shutil.rmtree(root)
run('xcrun','simctl','delete',device_id)
assert device_id not in devices()
assert not device_root.exists()
for root in roots: assert not root.exists()
for p in ledger['retainedWorkingCaches']: assert pathlib.Path(p).is_dir()
for row in receipt['files']:
    if row['path'].endswith('.png'):
        assert hashlib.sha256((repo/row['path']).read_bytes()).hexdigest() == row['sha256']
ledger.update(status='complete',availableBytesAfter=available(),checkedAtUTC=now())
ledger['measuredAvailableBytesRecovered'] = ledger['availableBytesAfter']-ledger['availableBytesBefore']
for field in ['regularFilePaths','symbolicLinks','logicalFileBytes','uniqueInodeAllocatedBytes']:
    ledger[field] = sum(r[field] for r in summaries)
(evidence/'storage-cleanup.json').write_text(json.dumps(ledger,indent=2)+'\n')
print(json.dumps({k:ledger[k] for k in ['status','availableBytesBefore','availableBytesAfter','measuredAvailableBytesRecovered','regularFilePaths','symbolicLinks','logicalFileBytes','uniqueInodeAllocatedBytes']}))
