"""Small synthetic checks of draft host observers; never executes a native producer."""
import ast
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import threading
import time
import traceback
from types import SimpleNamespace
from unittest.mock import patch

base = Path(__file__).resolve().parent
source_path = base / 'health-recovery-error-held-r4-driver.py.draft'
source_bytes = source_path.read_bytes()
tree = ast.parse(source_bytes)
fixture = Path('/tmp/LumenHeldHostDraftSelfChecksR4')
assert not fixture.exists()
fixture.mkdir(mode=0o700)
digest = lambda data: hashlib.sha256(data).hexdigest()
selected = {'metadata_tree', 'observe_retired_cleanup', 'snapshot', 'exact_success_tree'}
definitions = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in selected]
assert len(definitions) == len(selected)
context = dict(json=json, os=os, stat=stat, time=time, Path=Path, digest=digest, sha=digest, base64=base64)
exec(compile(ast.Module(body=definitions, type_ignores=[]), str(source_path), 'exec'), context)
results = []


def private_fixture(name):
    group = fixture / name
    root = group / 'LumenData'
    private = root / '.health-recovery' / 'synthetic-copy' / 'meals.json'
    private.parent.mkdir(parents=True)
    private.write_bytes(b'{"synthetic":true}')
    metadata = context['metadata_tree'](root)
    context['preservation_metadata'] = {'.health-recovery/synthetic-copy/meals.json': metadata['.health-recovery/synthetic-copy/meals.json']}
    return group, root, private


group, root, private = private_fixture('hardlink-lifecycle')
retired = group / 'LumenData.retired-synthetic'
retired.mkdir()
old_link = retired / 'meals.json'
os.link(private, old_link)
assert private.stat().st_nlink == 2


def finish_synthetic_cleanup():
    old_link.unlink()
    retired.rmdir()


timer = threading.Timer(0.05, finish_synthetic_cleanup)
timer.start()
try:
    observed = context['observe_retired_cleanup'](root)
finally:
    timer.join()
counts = [r['privateMetadata']['.health-recovery/synthetic-copy/meals.json']['st_nlink'] for r in observed['observations']]
assert observed['ready'] and counts[0] == 2 and counts[-1] == 1
results.append({'check': 'Actual hardlink2-to1 lifecycle accepted after synthetic retired-root removal', 'result': 'PASS', 'observedLinkCounts': counts})

group, root, private = private_fixture('vanished-after-glob')
original_glob = Path.glob
witness = {'vanishedLstatRequested': False}


class Vanished:
    def lstat(self):
        witness['vanishedLstatRequested'] = True
        raise FileNotFoundError('Synthetic directory disappeared after glob')


def vanished_glob(path, pattern):
    if path == group and pattern == 'LumenData.retired-*':
        return iter([Vanished()])
    return original_glob(path, pattern)


with patch.object(Path, 'glob', vanished_glob):
    observed = context['observe_retired_cleanup'](root)
assert witness['vanishedLstatRequested'] and observed['ready']
results.append({'check': 'Vanished-after-glob directory is safely already gone', 'result': 'PASS'})

group, root, private = private_fixture('timeout-retains-observations')
(group / 'LumenData.retired-still-present').mkdir()
try:
    context['observe_retired_cleanup'](root)
    raise RuntimeError('Expected finite timeout rejection')
except AssertionError as error:
    assert 'finite3s guard' in str(error)
partial = context['retired_cleanup']
assert not partial['ready'] and len(partial['observations']) >= 2
results.append({'check': 'Expected finite timeout rejects and retains partial observer samples', 'result': 'PASS', 'retainedSamples': len(partial['observations'])})

root = fixture / 'exact-tree' / 'LumenData'
root.mkdir(parents=True)
(root / 'water.json').write_bytes(b'[]')
context['protected_before'] = context['snapshot'](root, current=False)
context['fault_observation'] = {'currentMetadataBefore': context['metadata_tree'](root)}
receipt = root / '.health-recovery-history' / 'synthetic.json'
receipt.parent.mkdir()
receipt.write_bytes(b'{}')
private_audit = {'privatePriorFiles': {}, 'privateDamagedCurrentFiles': {}}
context['exact_success_tree'](root, receipt, private_audit, {'photoDigests': {}})
(root / 'unexpected.txt').write_bytes(b'synthetic unwanted file')
try:
    context['exact_success_tree'](root, receipt, private_audit, {'photoDigests': {}})
    raise RuntimeError('Unexpected file was accepted')
except AssertionError:
    pass
(root / 'unexpected.txt').unlink()
(root / '.health-recovery' / 'pending-orphan').mkdir(parents=True)
try:
    context['exact_success_tree'](root, receipt, private_audit, {'photoDigests': {}})
    raise RuntimeError('Unexpected empty directory was accepted')
except AssertionError:
    pass
results.append({'check': 'Exact tree accepts declared files, rejects extra file and empty orphan directory', 'result': 'PASS'})

# Run only the actual terminal export/retention loop with a fake exporter.
# The supplied .bin payloads are deliberately not screenshots or native results.
raw = fixture / 'export-raw'
output = fixture / 'export-canonical'
raw.mkdir(); output.mkdir()
for suffix in ['PNG', 'JSON']:
    directory = raw / ('Synthetic' + suffix)
    directory.mkdir()
    names = ['missing.bin', 'later.bin'] if suffix == 'PNG' else ['readback.json']
    manifest = [{'testIdentifier': 'SyntheticHostSelfCheck/notNative()',
                 'attachments': [{'exportedFileName': n} for n in names]}]
    (directory / 'manifest.json').write_text(json.dumps(manifest))
    (directory / names[-1]).write_bytes(b'{}' if suffix == 'JSON' else b'synthetic bytes, not an image')
calls = []


def fake_export(command, **kwargs):
    calls.append(command)
    if command[-1] == '*.png':
        raise subprocess.CalledProcessError(1, command)
    return SimpleNamespace(returncode=0)


export_context = dict(Path=Path, json=json, digest=digest, raw=raw, base=output,
                      stem='Synthetic', prefix='synthetic-host-selfcheck',
                      a=SimpleNamespace(source='synthetic-only'), subprocess=SimpleNamespace(run=fake_export, DEVNULL=subprocess.DEVNULL),
                      result=fixture/'fake-never-executed.xcresult',
                      terminal_errors=[], terminal_outcome={'status': 'unaccepted'}, traceback=traceback,
                      save_terminal=lambda: None)
loop = [n for n in tree.body if isinstance(n, ast.For) and ast.unparse(n.target) == '(suffix, pattern)']
assert len(loop) == 1
exec(compile(ast.Module(body=loop, type_ignores=[]), str(source_path), 'exec'), export_context)
png = json.loads((output / 'synthetic-host-selfcheck-png-retention-index.json').read_text())
js = json.loads((output / 'synthetic-host-selfcheck-json-retention-index.json').read_text())
assert not png['complete'] and not png['exportSucceeded'] and len(png['retained']) == len(png['failedEntries']) == 1
assert js['complete'] and len(js['retained']) == 1 and len(calls) == 2
assert (output / 'synthetic-host-selfcheck-png-export-manifest.json').read_bytes() == (raw / 'SyntheticPNG' / 'manifest.json').read_bytes()
assert len(export_context['terminal_errors']) == 2
verification = [n for n in tree.body if isinstance(n, ast.Try) and n.body and isinstance(n.body[0], ast.Assert)]
assert len(verification) == 1
try:
    exec(compile(ast.Module(body=verification, type_ignores=[]), str(source_path), 'exec'), export_context)
    raise RuntimeError('Partial export was accepted')
except AssertionError:
    pass
assert export_context['terminal_outcome']['status'].startswith('FAILED')
results.append({'check': 'Partial export and missing first attachment preserve original manifest, later payload and independent JSON; final acceptance rejects', 'result': 'PASS', 'recordedErrors': len(export_context['terminal_errors'])})

report = {'status': 'PASS five focused synthetic host observer/retention checks',
          'draft': source_path.name, 'draftSHA256': digest(source_bytes), 'checks': results,
          'fixtureDirectory': str(fixture), 'fixtureLogicalBytes': sum(p.stat().st_size for p in fixture.rglob('*') if p.is_file()),
          'scope': 'AST-extracted host helper/retention code only, tiny synthetic files and fake exporter. No native producer/module execution, app build, simulator action, screenshot, cancellation or product acceptance.',
          'checkedAt': time.time()}
(base / 'health-recovery-error-held-r4-selfcheck-r4-outcome.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
