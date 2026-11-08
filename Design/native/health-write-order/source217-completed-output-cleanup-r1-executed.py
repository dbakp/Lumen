"""Remove named disposable217 output only after the final exact remote checkpoint."""
from pathlib import Path
import gzip, hashlib, json, os, shutil, stat, subprocess, time

repo = Path('/Users/davidbakposada/Documents/ChatGPT/Lumen')
base = repo / 'Design/native/health-write-order'
raw = Path('/tmp/LumenBatch44Checks')
sha = lambda data: hashlib.sha256(data).hexdigest()
names = json.loads(Path('/tmp/lumen217-completion-publish-paths.json').read_text())
names = sorted(set(names + json.loads(Path('/tmp/lumen217-mixed-publish-paths.json').read_text()) +
                   ['Design/native/health-write-order/durable-source-r217.json',
                    'Design/native/health-write-order/durable-source-r217.json.gz']))
proofs = []
for name in names:
    path = repo / name
    assert not path.is_symlink()
    data = path.read_bytes()
    assert subprocess.check_output(['git', 'show', 'origin/main:' + name], cwd=repo) == data, name
    proofs.append({'file': name, 'bytes': len(data), 'sha256': sha(data)})

targets = []
for stem, prefix in [('HealthMixedIneligibleSource217R1', 'health-mixed-ineligible-source217r1'),
                     ('HealthErrorStateLegacySource217R2', 'health-error-state-legacy-source217r2')]:
    for kind in ['images', 'readbacks']:
        for row in json.loads((base / (prefix + '-' + kind + '.json')).read_bytes()):
            assert row['individuallyOpened'] is True
            assert Path(row['raw']).read_bytes() == (base / row['file']).read_bytes()
    for kind in ['png', 'json']:
        assert (raw / (stem + kind.upper()) / 'manifest.json').read_bytes() == gzip.decompress(
            (base / (prefix + '-' + kind + '-original-manifest.json.gz')).read_bytes())
    assert (raw / (stem + '.log')).read_bytes() == gzip.decompress((base / (stem + '.log.gz')).read_bytes())
    assert json.loads((raw / (stem + '-summary.json')).read_bytes()) == json.loads(
        (base / (prefix + '-summary.json')).read_bytes())
    targets += [raw / (stem + suffix) for suffix in ['.xcresult', 'PNG', 'JSON', '.log', '-summary.json']]

# Release completed and independently reviewed82; native/package caches are reused next.
release = json.loads((base / 'health-current-release-source217-r1-audit.json').read_bytes())
binary = Path('/tmp/LumenBatch37Release/Build/Products/Release-iphoneos/Lumen.app/Lumen').read_bytes()
assert sha(binary) == release['executableSHA256'] and len(binary) == release['executableBytes']
assert (raw / 'Source217UnsignedReleaseR1.log').read_bytes() == gzip.decompress(
    (base / 'source217-unsigned-release-r1-build.log.gz').read_bytes())
settings = json.loads((base / 'source217-unsigned-release-r1-settings-audit.json').read_bytes())
assert sha((raw / 'Source217UnsignedReleaseR1Settings.json').read_bytes()) == settings['rawSettingsSHA256']
targets += [Path('/tmp/LumenBatch37Release'), raw / 'Source217UnsignedReleaseR1.log',
            raw / 'Source217UnsignedReleaseR1Settings.json', raw / 'Source217UnsignedReleaseR1Settings.log',
            raw / 'Source217UnsignedReleaseR1Audit.log', raw / 'Source217MixedIneligibleNativeBuildR1.log',
            raw / 'Source217NormalOriginDataR2Driver.log']
assert len(targets) == 17

processes = subprocess.check_output(['ps', '-axo', 'pid,args'], text=True)
assert not any(('xcodebuild' in line or 'swift-frontend' in line) and
               any(str(p) in line for p in targets) for line in processes.splitlines()
               if 'zsh -lc' not in line and 'python3 -' not in line)
inventory, seen = [], set()
allocated = regular = symlinks = 0
for target in targets:
    assert target.exists() and not target.is_symlink()
    files = [target] if target.is_file() else []
    if target.is_dir():
        for parent, dirs, entries in os.walk(target, followlinks=False):
            for name in list(dirs):
                if (Path(parent) / name).is_symlink():
                    symlinks += 1
                    dirs.remove(name)
            files.extend(Path(parent) / name for name in entries)
    for path in files:
        facts = path.lstat()
        if stat.S_ISLNK(facts.st_mode):
            symlinks += 1
            continue
        assert stat.S_ISREG(facts.st_mode)
        regular += 1
        key = (facts.st_dev, facts.st_ino)
        if key not in seen:
            allocated += facts.st_blocks * 512
            seen.add(key)
    scan = subprocess.run(['lsof', '-nP', '+D', str(target)] if target.is_dir()
                          else ['lsof', '-nP', str(target)], capture_output=True, text=True)
    assert scan.returncode == 1 and not scan.stdout, 'Open task output: ' + str(target)
    inventory.append({'path': str(target), 'regularEntries': len(files)})

before = shutil.disk_usage(repo).free
for target in targets:
    shutil.rmtree(target) if target.is_dir() else target.unlink()
    assert not target.exists()
after = shutil.disk_usage(repo).free
result = {'status': 'PASS named completed217 raw duplicates and Release output removed after exact backups',
          'exactGithubMain': subprocess.check_output(['git', 'rev-parse', 'origin/main'], cwd=repo, text=True).strip(),
          'exactBackupPaths': proofs, 'removed': inventory, 'regularFiles': regular,
          'symlinksRemovedWithoutFollowing': symlinks, 'uniqueAllocatedRegularBytes': allocated,
          'availableBytesBefore': before, 'availableBytesAfter': after, 'observedFreeDeltaBytes': after - before,
          'positiveRecoveryCreditBytes': min(allocated, max(0, after - before)),
          'creditConvention': 'min(allocated,positive observed volume free change); concurrent volume users may affect delta',
          'preserved': 'Canonical34originals/full9691Bnativehelpers/manifests/logs/source/fullreports retained. Native/package caches immediately reused; simulator state, skill, real inputs, original191unbacked video, unrelated projects and personal data untouched. Raw settings retain compact selected facts/provenance only. No cleanup-only build.',
          'checkedAt': time.time()}
(base / 'source217-completed-output-cleanup-r1.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({key: result[key] for key in ['status', 'regularFiles', 'symlinksRemovedWithoutFollowing',
    'uniqueAllocatedRegularBytes', 'observedFreeDeltaBytes', 'positiveRecoveryCreditBytes', 'availableBytesAfter']}), flush=True)
