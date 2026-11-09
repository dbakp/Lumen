"""Exact current native checkpoint gate; no build, device, or mutation actions."""
import hashlib
import json
from pathlib import Path
import subprocess


def require_native_checkpoint(base, repo, proof):
    commit = proof['commit']
    for ref in ['HEAD', 'origin/main']:
        actual = subprocess.check_output(['git', 'rev-parse', ref], cwd=repo, text=True).strip()
        assert actual == commit, ('native prerequisite commit mismatch', ref)
    assert proof['source'] == 'durable-source-r260.json'
    names = [
        'health-retained-review-owner-source260-round2-part184-sheet-dismiss-native.json',
        'source260-root-part184-review.json',
    ]
    verified = []
    for name in names:
        path = base / name
        assert path.is_file() and not path.is_symlink()
        relative = str(path.resolve().relative_to(Path(repo).resolve()))
        rows = [row for row in proof['proofs'] if row['file'] == relative]
        assert len(rows) == 1
        row = rows[0]
        assert type(row['bytes']) is int and row['bytes'] > 0
        data = path.read_bytes()
        assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
        git_data = subprocess.check_output(['git', 'cat-file', 'blob', commit + ':' + relative], cwd=repo)
        assert git_data == data, ('native prerequisite Git bytes mismatch', name)
        report = json.loads(data)
        assert report['source'] == 'durable-source-r260.json' and report['case'] == 'sheet-dismiss'
        assert report['scopedNativeAcceptance'] is True
        assert report['globalProductAcceptance'] is False
        if name == names[0]:
            assert report['part'] == 184 and type(report['part']) is int
            assert report['requiredCorrectionsForThisScopedCase'] == []
        verified.append({'file': relative, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    return {'commit': commit, 'verifiedNativeReports': verified}
