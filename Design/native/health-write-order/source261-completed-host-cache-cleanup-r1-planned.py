"""Remove only completed, backed host Swift controls and their private module cache.

One execution only. No simulator, app Debug/package cache, global cache or video.
"""
from pathlib import Path
import gzip
import hashlib
import json
import os
import shutil
import stat
import subprocess
import time

B = Path(__file__).resolve().parent; R = B.parents[2]
output = B / 'source261-completed-host-cache-cleanup-r1.json'; assert not output.exists()
roots = [Path('/private/tmp/LumenRetainedBackendBarrier261'), Path('/private/tmp/LumenRetainedBackendBarrier261R2')]
report = {'status':'FAILED cleanup; inspect removedPaths', 'removedPaths':[], 'errors':[],
          'scope':'Completed task-owned host native-helper control binaries/source mirrors and private Swift ModuleCache only',
          'preserved':'Current simulator Debug/packages, repository/current inputs/provider/design skill, unbacked191/219 videos, every simulator/user/global cache',
          'startedAt':time.time()}
try:
    commit = subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip()
    remote = subprocess.check_output(['git','ls-remote','origin','refs/heads/main'],cwd=R,text=True).split()[0]
    assert commit == remote
    report['verifiedPublishedMain'] = commit
    names = ['LumenUITests/LumenSmokeTests.swift', str((B/'source261-uitest-before-copy-binding-r1.swift.txt.gz').relative_to(R))]
    for n in (1,2,3):
        for suffix in (f'source261-native-barrier-controls-r{n}.json',f'source261-native-barrier-controls-r{n}-executed.py',f'source261-native-barrier-host-controls-r{n}.swift'):
            names.append(str((B/suffix).relative_to(R)))
    report['canonicalInputs'] = []
    for name in names:
        data = (R/name).read_bytes()
        blob = subprocess.check_output(['git','cat-file','blob',commit+':'+name],cwd=R)
        assert data == blob
        report['canonicalInputs'].append({'file':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
    old = gzip.decompress((B/'source261-uitest-before-copy-binding-r1.swift.txt.gz').read_bytes())
    current = (R/'LumenUITests/LumenSmokeTests.swift').read_bytes()
    prefix = b'import Foundation\nimport XCTest\nimport CryptoKit\nimport Darwin\n'
    report['sourceReconstructions'] = []
    for n, path in [(1,roots[0]/'actual-native-helper-controls.swift'),(2,roots[1]/'actual-native-helper-controls.swift'),(3,roots[1]/'actual-native-helper-controls-r3.swift')]:
        source = old if n < 3 else current
        helper = source[source.index(b'\n/// Test-runner transport only.'):]
        expected = prefix+helper+b'\n'+(B/f'source261-native-barrier-host-controls-r{n}.swift').read_bytes()
        assert path.read_bytes() == expected
        report['sourceReconstructions'].append({'control':n,'path':str(path),'bytes':len(expected),'sha256':hashlib.sha256(expected).hexdigest(),'matchesPublishedCanonicalInputs':True})
    process = subprocess.run(['pgrep','-x','swiftc|swift-frontend|xcodebuild|native-barrier-controls|native-barrier-controls-r3'],capture_output=True)
    report['processGuard'] = {'command':process.args,'exit':process.returncode,'stdout':process.stdout.decode(),'stderr':process.stderr.decode()}
    assert process.returncode == 1, 'A potentially relevant compiler/build/control process remains active'
    expected_names = [ {'actual-native-helper-controls.swift'},
                      {'ModuleCache.noindex','actual-native-helper-controls.swift','actual-native-helper-controls-r3.swift','native-barrier-controls','native-barrier-controls-r3'} ]
    entries = []; allocated = 0
    for root, expected in zip(roots, expected_names):
        assert root.resolve() == root and root.is_dir() and not root.is_symlink()
        assert {p.name for p in root.iterdir()} == expected
        for parent, dirs, files in os.walk(root,followlinks=False):
            for path in [Path(parent)] + [Path(parent)/name for name in files]:
                value = path.lstat()
                assert stat.S_ISREG(value.st_mode) or stat.S_ISDIR(value.st_mode)
                if stat.S_ISREG(value.st_mode): assert value.st_nlink == 1
                allocated += value.st_blocks * 512
                entries.append({'path':str(path),'kind':stat.S_IFMT(value.st_mode),'allocatedBytes':value.st_blocks*512})
            assert not any((Path(parent)/name).is_symlink() for name in dirs)
    assert shutil.rmtree.avoids_symlink_attacks
    report['entries'] = entries; report['allocatedBytes'] = allocated
    report['availableBeforeBytes'] = shutil.disk_usage(R).free
    for root in roots:
        shutil.rmtree(root); assert not os.path.lexists(root)
        report['removedPaths'].append(str(root))
    report['availableAfterBytes'] = shutil.disk_usage(R).free
    report['creditedRecoveredBytes'] = min(allocated,max(0,report['availableAfterBytes']-report['availableBeforeBytes']))
    report['priorAggregateCreditedRecoveredBytes'] = 17744531031
    report['aggregateCreditedRecoveredBytes'] = 17744531031 + report['creditedRecoveredBytes']
    report['status'] = 'SUPPORTED scoped completed host output/cache cleanup after exact Git backup'
except BaseException as error:
    import traceback
    report['errors'].append(traceback.format_exc())
finally:
    report['finishedAt'] = time.time()
    output.write_text(json.dumps(report,indent=2)+'\n')
print(report['status'], report.get('creditedRecoveredBytes',0), 'credited bytes')
assert report['status'].startswith('SUPPORTED'), report['errors']
