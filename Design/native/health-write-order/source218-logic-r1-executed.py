"""Fresh host compile/full suite for changed control source; not native/UI proof."""
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time
import traceback

repo = Path('/Users/davidbakposada/Documents/ChatGPT/Lumen')
base = repo / 'Design/native/health-write-order'
raw = Path('/tmp/LumenBatch44Checks')
source = json.loads((base / 'durable-source-r218.json').read_bytes())
sha = lambda value: hashlib.sha256(value).hexdigest()
target = base / 'source218-logic-r1-outcome.json'
assert not target.exists()
assert shutil.disk_usage(repo).free > 8 * 1024**3
outcome = {'status': 'RUNNING unaccepted current218hostlogic', 'source': 'durable-source-r218.json',
           'runs': [], 'physicalDeviceActions': False}


def verify():
    for group in ['files', 'fixtureInputs']:
        for name, row in source[group].items():
            path = repo / name
            assert path.is_file() and not path.is_symlink()
            data = path.read_bytes()
            assert len(data) == row['bytes'] and sha(data) == row['sha256'], name


def run(label, command):
    log = raw / ('Source218Logic' + label.title() + 'R1.log')
    assert not log.exists(), 'Do not restart a run'
    row = {'label': label, 'command': command, 'startedAt': time.time()}
    outcome['runs'].append(row)
    target.write_text(json.dumps(outcome, indent=2) + '\n')
    with log.open('xb') as stream:
        process = subprocess.Popen(command, cwd=repo, stdout=stream, stderr=subprocess.STDOUT)
        subprocess.Popen(['caffeinate', '-i', '-w', str(process.pid)])
        row['PID'] = process.pid
        print('Actual218hostlogic', label, 'PID', process.pid, flush=True)
        code = process.wait()
    data = log.read_bytes()
    retained = 'source218-logic-' + label + '-r1.log.gz'
    (base / retained).write_bytes(gzip.compress(data, mtime=0))
    text = data.decode(errors='replace')
    row.update(exitCode=code, log=retained, logBytes=len(data), logSHA256=sha(data),
               passLines=sum(line.startswith('PASS:') for line in text.splitlines()),
               terminalLines=text.splitlines()[-5:], finishedAt=time.time())
    target.write_text(json.dumps(outcome, indent=2) + '\n')
    assert code == 0, label
    verify()
    return text


try:
    verify()
    common = ['swift', 'build', '--scratch-path', '/tmp/LumenLogicBuild',
        '--cache-path', '/tmp/LumenLogicBuild/Cache', '--config-path', '/tmp/LumenLogicBuild/Config',
        '--security-path', '/tmp/LumenLogicBuild/Security', '--manifest-cache', 'local',
        '--force-resolved-versions', '--skip-update', '--jobs', '2']
    run('build', common + ['--product', 'LumenLogicChecks'])
    query = subprocess.run(common + ['--show-bin-path'], cwd=repo, capture_output=True, text=True)
    outcome['binaryPathQuery'] = {'command': common + ['--show-bin-path'], 'exit': query.returncode,
                                 'stdout': query.stdout, 'stderr': query.stderr}
    assert query.returncode == 0
    binary = Path(query.stdout.strip()) / 'LumenLogicChecks'
    assert binary.is_relative_to('/tmp/LumenLogicBuild') or binary.is_relative_to('/private/tmp/LumenLogicBuild')
    assert binary.is_file() and not binary.is_symlink()
    outcome['binary'] = {'path': str(binary), 'bytes': binary.stat().st_size, 'sha256': sha(binary.read_bytes())}
    focus = base / 'source218-origin-review-r1.json'
    assert not focus.exists()
    focus_text = run('review', [str(binary), '--health-origin-review', str(focus.relative_to(repo))])
    focus_value = json.loads(focus.read_bytes())
    assert len(focus_value['checks']) == 23 and all(row['passed'] is True for row in focus_value['checks'])
    assert 'PASS: 23 origin review checks' in focus_text
    outcome['focusReport'] = focus.name
    text = run('full', [str(binary)])
    cache = re.findall(r'^Health daily cache: (\d+) checks passed$', text, flags=re.M)
    today = re.findall(r'^Health today queries: (\d+) checks passed$', text, flags=re.M)
    assert cache == ['137'] and today == ['36']
    assert outcome['runs'][-1]['passLines'] == 2177
    assert 'All import, model, totals, history, plan, conversation, evidence, document and reminder checks passed.' in text
    assert sha(binary.read_bytes()) == outcome['binary']['sha256']
    outcome['fullComponents'] = {'individualPassLines': 2177, 'dailyCacheChecks': 137,
                                 'todayQueryChecks': 36, 'total': 2350}
    outcome['focusedReviewChecks'] = 23
    outcome['status'] = 'PASS fresh current218hostcompile/full2350; focused23 separate; no native/UI/Release acceptance'
except BaseException:
    outcome['status'] = 'FAILED or incomplete actual218hostlogic; no acceptance'
    outcome['failure'] = traceback.format_exc()
    raise
finally:
    outcome['scope'] = 'Changed BackupPackage text includes a read-only DEBUGsim getter; host branch excludes it. Fresh actual host execution still binds current full input bytes; actual simulator behavior requires separate cases.'
    outcome['availableBytesAfter'] = shutil.disk_usage(repo).free
    target.write_text(json.dumps(outcome, indent=2) + '\n')
print(outcome['status'], flush=True)
