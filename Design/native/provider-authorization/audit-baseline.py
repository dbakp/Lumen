"""Verify observed defects at exact baseline boundaries, never product acceptance."""
from pathlib import Path
import gzip
import hashlib
import json
import subprocess

base = Path(__file__).resolve().parent
repo = base.parents[2]


def read(name):
    return json.loads((base / name).read_text())


report = read('baseline-r3-report.json')
host = read('baseline-r3-host-readback.json')
assert report['status'] == 'Provider baseline reproduced' and report['host'] == host
assert host['tokenRequests'] == host['tokenResponses'] == 10 and host['holdTimeouts'] == 0
assert len(host['packets']) == 9
observations = {row['mode']: row for row in report['observations']}
assert len(observations) == 10
for mode, row in observations.items():
    assert row['outgoingRequests'] == (0 if mode == 'reset' else 1)
    assert row['replyAccepted'] == (mode != 'reset')
    assert row['accessState'] == ('expired-fixture' if mode == 'refresh-failure' else 'refreshed-fixture')
disconnect = observations['disconnect']
assert disconnect['selectedMode'] == 'onDevice' and not disconnect['refreshPresent'] and disconnect['expiryPresent']
assert observations['endpoint']['packet']['route'] == '/chat-b'
assert observations['model']['packet']['model'] == 'synthetic-provider-42-b'
assert observations['refresh-failure']['packet']['credential'] == 'expired-fixture'
assert not observations['reset']['refreshPresent'] and observations['reset']['expiryPresent']
for revision, passed in [(1, False), (2, False), (3, True)]:
    summary = read(f'baseline-r{revision}-' + ('summary.json' if passed else 'failed-summary.json'))
    assert summary['totalTestCount'] == 1 and summary['passedTests'] == int(passed)
    assert summary['failedTests'] == int(not passed) and summary['skippedTests'] == 0
assert read('baseline-r1-failed-report.json')['observations'] == []
assert len(read('baseline-r2-failed-report.json')['observations']) == 1
assert not read('baseline-r2-failed-report.json')['observations'][0]['replyAccepted']
assert read('baseline-r2-failed-report.json')['host'] == read('baseline-r2-host-readback.json')
original = read('baseline-source.json')
current = read('baseline-source-r3.json')
assert set(original['files']) == set(current['files'])
assert [path for path in current['files'] if current['files'][path] != original['files'][path]] == ['scripts/provider-authorization-server.py']
base_bytes = {}
for manifest, archive in [('baseline-source.json', 'baseline-instrumentation.json.gz'), ('baseline-source-r3.json', 'baseline-instrumentation-r3.json.gz')]:
    source = read(manifest)
    changes = json.loads(gzip.decompress((base / archive).read_bytes()))
    for path, facts in source['files'].items():
        if path in changes:
            data = changes[path].encode()
        else:
            if path not in base_bytes:
                base_bytes[path] = subprocess.check_output(['git', 'show', f'{source["baseCommit"]}:{path}'], cwd=repo)
            data = base_bytes[path]
        assert len(data) == facts['bytes'] and hashlib.sha256(data).hexdigest() == facts['sha256'], path
for row in read('baseline-r3-images.json'):
    assert hashlib.sha256((repo / row['repositoryPath']).read_bytes()).hexdigest() == row['sha256']
for archive in base.glob('*.gz'):
    with gzip.open(archive, 'rb') as stream:
        while stream.read(1024 * 1024):
            pass
print('Baseline defects verified at exact source boundaries: ten refreshes/nine chat packets, late write after disconnect/reset, changed endpoint/model and expired-token fallback. Not repaired or product acceptance.')
