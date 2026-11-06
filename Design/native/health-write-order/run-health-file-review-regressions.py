"""Current shared photo page regressions with separate actual source-file audits."""
import argparse
import base64
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys

p = argparse.ArgumentParser()
p.add_argument('--source', required=True)
p.add_argument('--build', required=True)
a = p.parse_args()
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = 'AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
source = json.loads((base / a.source).read_text())
build = json.loads((base / a.build).read_text())
digest = lambda data: hashlib.sha256(data).hexdigest()

def verify():
    assert build['source'] == a.source
    for name, row in source['files'].items():
        assert digest((repo / name).read_bytes()) == row['sha256'], name

completed = []
for mode, test in [('oriented', 'PhotoOriented'), ('invalid', 'PhotoUnavailable')]:
    verify()
    stem = 'HealthFilePhoto' + mode.title() + 'R1'
    prefix = 'health-file-photo-' + mode + '-r1'
    result = raw / (stem + '.xcresult')
    assert not result.exists()
    command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
               '-destination', 'platform=iOS Simulator,id=' + device,
               '-derivedDataPath', '/tmp/LumenBatch37Simulator',
               '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
               '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
               '-only-testing:LumenUITests/LumenSmokeTests/testHealthRecordReview' + test,
               '-resultBundlePath', str(result), 'test-without-building']
    print('START', mode, flush=True)
    with (raw / (stem + '.log')).open('xb') as stream:
        process = subprocess.Popen(command, cwd=repo, stdout=stream, stderr=subprocess.STDOUT)
        awake = subprocess.Popen(['caffeinate', '-d', '-i', '-w', str(process.pid)])
        code = process.wait()
    summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result)], text=True))
    (raw / (stem + '-summary.json')).write_text(json.dumps(summary, indent=2) + '\n')
    (base / (prefix + '-summary.json')).write_text(json.dumps(summary, indent=2) + '\n')
    assert code == 0 and summary['passedTests'] == 1 and summary['failedTests'] == 0
    verify()
    subprocess.run([sys.executable, str(base / 'run-health-record-ui-audit.py'), '--source', a.source,
                    '--build', a.build, '--device', 'main', '--mode', mode, '--trial', 'file-' + mode + '-r1'], check=True)
    for suffix, pattern in [('PNG', '*.png'), ('JSON', '*.json')]:
        with (raw / (stem + suffix + 'Export.log')).open('xb') as stream:
            subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result),
                            '--output-path', str(raw / (stem + suffix)), '--filter', pattern], stdout=stream, stderr=subprocess.STDOUT, check=True)
    subprocess.run([sys.executable, str(base / 'retain-health-record-attachments.py'), '--stem', stem,
                    '--prefix', prefix, '--source', a.source, '--png-dir', str(raw / (stem + 'PNG')),
                    '--json-dir', str(raw / (stem + 'JSON'))], check=True)
    if mode == 'oriented':
        audit = json.loads((base / 'health-record-main-file-oriented-r1-host-audit.json').read_text())
        jpeg = base / 'health-file-photo-oriented-r1-original.jpg'
        jpeg.write_bytes(base64.b64decode(audit['files']['previous/photos/synthetic-review-photo.jpg']['base64']))
        images = json.loads((base / (prefix + '-images.json')).read_text())
        readbacks = json.loads((base / (prefix + '-readbacks.json')).read_text())
        image = next(row for row in images if 'health-record-oriented-jpeg' in row['metadata']['suggestedHumanReadableName'])
        frame = next(row for row in readbacks if 'health-record-oriented-frame' in row['metadata']['suggestedHumanReadableName'])
        subprocess.run([sys.executable, str(base / 'verify-health-record-oriented-pixels.py'),
                        '--image', str(base / image['file']), '--jpeg', str(jpeg), '--frame', str(base / frame['file']),
                        '--output', str(base / 'health-file-photo-oriented-r1-pixel-audit.json')], check=True)
    for path in raw.glob(stem + '*.log'):
        (base / (path.name + '.gz')).write_bytes(gzip.compress(path.read_bytes(), mtime=0))
    completed.append({'mode': mode, 'prefix': prefix, 'test': test, 'source': a.source, 'passed': 1})
    (base / 'health-file-photo-r1-outcome.json').write_text(json.dumps({
        'status': 'passed requested cases' if len(completed) == 2 else 'progress; one case remains',
        'source': a.source, 'build': a.build, 'cases': completed,
        'scope': 'Retained-copy shared photo page regression only: real EXIF-oriented JPEG rendering and actual invalid-photo error. No selected-backup-photo recovery, held typed-read cancellation, all-domain or device acceptance.'
    }, indent=2) + '\n')
    print('TERMINAL PASS', mode, flush=True)
