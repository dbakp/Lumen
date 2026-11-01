import pathlib, subprocess, os, stat, json, hashlib, gzip, datetime, shutil, sys

repo = pathlib.Path('/Users/davidbakposada/Documents/ChatGPT/Lumen')
evidence = repo / 'Design/native/consent-preferences'
device_id = '27A46A83-C8F5-4817-8F11-C5CC90A1D0B7'
roots = [pathlib.Path('/tmp') / n for n in ['LumenBatch38Checks', 'LumenBatch38Release', 'LumenBatch38LogicBuild']]
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
    pid, command = line.strip().split(None, 1)
    executable = command.split(None, 1)[0]
    name = pathlib.Path(executable).name
    build_tool = name in ['xcodebuild', 'swift-frontend', 'swiftc', 'swift', 'swift-run', 'swift-build', 'xcresulttool']
    owned_binary = executable.startswith(('/tmp/LumenBatch38LogicBuild/', '/private/tmp/LumenBatch38LogicBuild/'))
    exporter = name.startswith('python') and '/tmp/LumenBatch38Checks/retain-captures.py' in command
    if any(n in command for n in ['LumenBatch37', 'LumenBatch38']) and (build_tool or owned_binary or exporter):
        raise RuntimeError('Active producer: '+line)
report_paths = {}
for name in ['native-backend-provenance.json', 'native-backend-provenance-r12.json']:
    proof = json.loads((evidence/name).read_text())
    raw = pathlib.Path(proof['rawPath'])
    assert str(raw).startswith('/Users/davidbakposada/Library/Developer/CoreSimulator/Devices/AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481/data/Containers/Data/Application/')
    assert raw.name == 'Lumen-preference-native-report.json' and raw.parent.name == 'tmp'
    report_paths.setdefault(raw, set()).add(proof['sha256'])
report_rows = []
for raw, hashes in report_paths.items():
    if not raw.exists(): continue
    assert raw.is_file() and not raw.is_symlink()
    data = raw.read_bytes(); digest = hashlib.sha256(data).hexdigest()
    assert digest in hashes, str(raw)
    report_rows.append(dict(path=str(raw),sha256=digest,bytes=len(data)))
before_devices = devices()
assert before_devices[device_id]['name'] == 'Lumen Batch38 compact verification'
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
ledger = dict(status='inventory complete; deletion starting',applicationCommit=head,verifiedGitBlobs=receipt['checkedFiles'],roots=summaries,inventoryFile='cleanup-inventory.jsonl.gz',inventorySHA256=hashlib.sha256(inventory).hexdigest(),availableBytesBefore=available(),startedUTC=now(),retainedWorkingCaches=['/tmp/LumenBatch37Simulator','/tmp/LumenBatch37Packages'],notes=['No symbolic-link target followed; delete only this batch-created compact simulator through simctl.','Available-volume change is separate from logical/unique-inode accounting and includes APFS/concurrent effects.','Keep one simulator build cache and its pinned dependency checkout for immediate conversation/archive work. No cleanup-only build.'],preserved=['Working repository, useful originals, compact outcomes/source/logs, current inputs and supplied skill/archive','Canonical research/model/source/environment/dataset/frozen inputs','Primary, Watch, Taskfold and other simulators/shared runtimes; unrelated projects, personal files and global/system/browser/application caches'])
(evidence/'storage-cleanup.json').write_text(json.dumps(ledger,indent=2)+'\n')
ledger['syntheticNativeReports'] = report_rows
for row in report_rows:
    raw = pathlib.Path(row['path'])
    assert not raw.is_symlink() and hashlib.sha256(raw.read_bytes()).hexdigest() == row['sha256']
    raw.unlink()
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
