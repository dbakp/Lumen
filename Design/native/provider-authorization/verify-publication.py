"""Read back one explicitly published commit before scoped local cleanup."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('commit', help='Exact intended published HEAD')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
base = Path(__file__).resolve().parent
repo = base.parents[2]

def run(*command):
    return subprocess.check_output(command, cwd=repo)

def api(path):
    return json.loads(run('gh', 'api', path))

head = run('git', 'rev-parse', 'HEAD').decode().strip()
assert args.commit == head, 'Pass the exact intended HEAD'
assert not run('git', 'status', '--porcelain').strip(), 'Publish a clean coherent commit first'
reference = api('repos/dbakp/Lumen/git/ref/heads/main')
assert reference['object']['sha'] == head, 'Remote main differs; do not delete local evidence'
commit = api('repos/dbakp/Lumen/git/commits/' + head)
tree = run('git', 'rev-parse', 'HEAD^{tree}').decode().strip()
assert commit['tree']['sha'] == tree
remote = api('repos/dbakp/Lumen/git/trees/' + tree + '?recursive=1')
assert remote['sha'] == tree and not remote.get('truncated', False)
remote_files = {row['path']: row for row in remote['tree'] if row['type'] == 'blob'}
source = json.loads((base / 'connection-source-r43.json').read_text())
for name, facts in source['files'].items():
    data = (repo / name).read_bytes()
    assert len(data) == facts['bytes'] and hashlib.sha256(data).hexdigest() == facts['sha256'], name
needed = set(source['files'])
needed.update(str(path.relative_to(repo)) for path in base.rglob('*') if path.is_file())
needed.update([
    'README.md', 'AGENTS.md', 'Design/DIRECTION.md', 'docs/CONTINUE_ON_NEW_COMPUTER.md',
    'docs/ROADMAP.md', 'docs/VERIFICATION.md', 'scripts/publish-batches.sh',
    'Design/native/health-write-order/next-durable-audit.json',
    'Design/native/health-write-order/durable-api-investigation-r1.json',
])
rows = []
for name in sorted(needed):
    path = repo / name
    assert path.is_file() and not path.is_symlink(), name
    data = path.read_bytes()
    blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    assert name in remote_files and remote_files[name]['sha'] == blob, name
    rows.append({'path': name, 'gitBlobSHA1': blob, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)})
assert not run('git', 'status', '--porcelain').strip(), 'Working tree changed during verification'
assert api('repos/dbakp/Lumen/git/ref/heads/main')['object']['sha'] == head
result = {
    'status': 'passed', 'checkedAtUTC': datetime.now(timezone.utc).isoformat(),
    'commit': head, 'rootTree': tree, 'githubMainMatches': True, 'githubTreeMatches': True,
    'verifiedRequiredBlobs': len(rows), 'requiredBlobs': rows,
    'source': 'connection-source-r43.json', 'applicationSource': 'connection-source-r41.json',
    'method': 'Fresh authenticated GitHub REST ref/commit/untruncated recursive-tree reads; '
              'every required local source/evidence byte stream matches its remote Git blob identity.',
    'scope': 'Checked current source, original failures, screenshots, complete retained primary logs, '
             'source archives, helpers, acceptance/review/Release evidence and continuation policy. '
             'No cleanup performed and no live-provider/device/whole-product acceptance implied.',
}
output = args.output or base / 'repair-publication-readback.json'
output.write_text(json.dumps(result, indent=2) + '\n')
print('Verified remote main/root and', len(rows), 'required blob identities for', head)
