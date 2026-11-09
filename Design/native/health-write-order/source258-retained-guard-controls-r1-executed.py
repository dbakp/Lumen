"""Compile the actual extracted diagnostic-context property against Foundation."""
from pathlib import Path
import hashlib, json, subprocess, tempfile
B = Path(__file__).resolve().parent; R = B.parents[2]
source = R / 'Lumen/Views/HealthRetainedReviewUIFixture.swift'; raw = source.read_bytes(); text = raw.decode()
start = text.index('    static var mode: String? {'); opening = text.index('{', start); depth = 1; end = opening + 1
while depth:
    if text[end] == '{': depth += 1
    elif text[end] == '}': depth -= 1
    end += 1
body = text[opening + 1:end - 1].replace('let args = ProcessInfo.processInfo.arguments', 'let args = arguments')
flag = '-health-retained-review-owner-ui'
base = ['-resetForUITests', '-health-review-records-fixture', flag]
fixtures = [(base + [kind], kind) for kind in ['children', 'pending-back', 'sheet-dismiss']]
fixtures += [([], None), ([flag, 'children'], None), (base, None), (base + ['unknown'], None),
             (base + ['children', flag, 'children'], None), (base[1:] + ['children'], None),
             (['-resetForUITests', flag, 'children'], None)]
program = 'import Foundation\nlet flag = "' + flag + '"\nfunc mode(_ arguments: [String]) -> String? {' + body + '}\n'
program += 'let cases = ' + json.dumps([args for args, expected in fixtures]) + '\n'
program += 'let values = cases.map { mode($0) as Any? ?? NSNull() }; let data = try JSONSerialization.data(withJSONObject: values); print(String(decoding: data, as: UTF8.self))\n'
with tempfile.TemporaryDirectory(prefix='lumen258-retained-guard-') as folder:
    swift = Path(folder) / 'guard.swift'; binary = Path(folder) / 'guard'; swift.write_text(program)
    compile = subprocess.run(['xcrun', 'swiftc', str(swift), '-o', str(binary)], capture_output=True)
    assert compile.returncode == 0, compile.stderr.decode()
    run = subprocess.run([str(binary)], capture_output=True); assert run.returncode == 0
    observed = json.loads(run.stdout); assert observed == [expected for args, expected in fixtures]
report = {'status': 'PASS actual extracted native mode guard', 'count': len(fixtures),
          'source': {'file': str(source.relative_to(R)), 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()},
          'extractedProgram': program, 'fixtures': [{'arguments': args, 'expected': expected, 'observed': observed[i]} for i, (args, expected) in enumerate(fixtures)],
          'compileExit': compile.returncode, 'compileStdout': compile.stdout.decode(), 'compileStderr': compile.stderr.decode(),
          'runExit': run.returncode, 'runStdout': run.stdout.decode(), 'runStderr': run.stderr.decode(),
          'scope': 'Actual extracted context property and Foundation execution only, not full fixture/SwiftUI/native launch acceptance.'}
target = B / 'source258-retained-guard-controls-r1.json'; assert not target.exists(); target.write_text(json.dumps(report, indent=2) + '\n')
print(report['status'], report['count'])
