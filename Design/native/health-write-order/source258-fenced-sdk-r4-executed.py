"""Typecheck whole current app/test independently, with exact before/after fences."""
from pathlib import Path
import concurrent.futures, hashlib, json, subprocess, time
B = Path(__file__).resolve().parent
R = B.parents[2]


def check(kind, command):
    def sources():
        return {str(Path(f).relative_to(R)) if Path(f).is_relative_to(R) else f:
                {'bytes': len(Path(f).read_bytes()), 'sha256': hashlib.sha256(Path(f).read_bytes()).hexdigest()}
                for f in command if f.endswith('.swift')}
    before = sources(); started = time.time()
    p = subprocess.Popen(command, cwd=R, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = p.communicate(); after = sources()
    value = {'kind': kind, 'command': command, 'pid': p.pid, 'exit': p.returncode,
             'sourcesBefore': before, 'sourcesAfter': after, 'sourceFenceExact': before == after,
             'stdout': out.decode(), 'stderr': err.decode(), 'startedAt': started, 'finishedAt': time.time(),
             'scope': 'Whole actual source SDK typing, actual dependency modules/generated assets, no stubs. No full link/build/native acceptance.'}
    value['status'] = 'PASS' if p.returncode == 0 and before == after else 'FAILED'
    target = B / ('source258-' + kind + '-sdk-r4.json'); assert not target.exists()
    target.write_text(json.dumps(value, indent=2) + '\n')
    return {'kind': kind, 'status': value['status'], 'exit': p.returncode, 'sourceCount': len(before)}


if __name__ == '__main__':
    app = json.loads((B / 'source258-whole-app-sdk-r2-command.json').read_bytes())
    test = json.loads((B / 'source239-test-typecheck-r1.json').read_bytes())['command'][:-1] + [str(R / 'LumenUITests/LumenSmokeTests.swift')]
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(check, 'whole-app', app), pool.submit(check, 'uitest', test)]
        results = [future.result() for future in futures]
    print(json.dumps(results)); raise SystemExit(any(row['status'] != 'PASS' for row in results))
