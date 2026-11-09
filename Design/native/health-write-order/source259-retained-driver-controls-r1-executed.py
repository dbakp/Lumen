"""Actual driver.main with injected OS/native queries, using real temporary files.

These controls never launch Xcode, touch a simulator or validate native output.
They exercise caller retention, terminal persistence and per-peer failures.
"""
from pathlib import Path, PosixPath
import base64, hashlib, importlib.util, json, subprocess, sys, tempfile, time, types

B = Path(__file__).resolve().parent
parser = __import__('argparse').ArgumentParser(description=__doc__)
parser.add_argument('--driver', required=True)
parser.add_argument('--output', required=True)
parser.add_argument('--expect-defects', action='store_true')
a = parser.parse_args()
assert Path(a.driver).name == a.driver and Path(a.output).name == a.output
actual = B / a.driver
rows = []


def trial(fault):
    with tempfile.TemporaryDirectory(prefix='lumen259-driver-injected-') as folder:
        root = Path(folder); base = root / 'canonical'; raw = root / 'raw'; group = root / 'group'
        for directory in [base, raw, group]: directory.mkdir()
        app = root / 'app'; test = root / 'test'; app.write_bytes(b'injected app'); test.write_bytes(b'injected test')
        receipt = {'source': 'durable-source-r258.json', 'buildExit': 0, 'testBinary': str(test),
                   'sha256': hashlib.sha256(app.read_bytes()).hexdigest(), 'binaryBytes': app.stat().st_size,
                   'testBinarySHA256': hashlib.sha256(test.read_bytes()).hexdigest(), 'testBinaryBytes': test.stat().st_size}
        (base / 'health-target-change-source258-r1-build.json').write_text(json.dumps(receipt))
        (base / 'source258-build-exact-github.json').write_text(json.dumps({'source': 'durable-source-r258.json', 'commit': 'injected-commit'}))
        (base / 'retained-owner-protocol-r1.py').write_bytes((B / 'retained-owner-protocol-r1.py').read_bytes())
        class MappedPath(PosixPath):
            def __new__(cls, *args):
                value = PosixPath(*args)
                if str(value) == '/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/Lumen.app/Lumen': value = app
                return super().__new__(cls, value)
            def write_bytes(self, data):
                if fault == 'peer-copy-raise' and self.name.endswith('-original-10-bad.png'):
                    raise OSError('injected first peer copy failure')
                return super().write_bytes(data)
        spec = importlib.util.spec_from_file_location('actual_retained_driver_' + fault.replace('-', '_'), actual)
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        module.B = MappedPath(base); module.R = MappedPath(root); module.RAW = MappedPath(raw); module.Path = MappedPath
        module.verify_source = lambda: 1101
        module.provider = lambda: {'bytes': 4992, 'sha256': 'injected provider'}
        calls = []
        class Native:
            pid = 424242
            def __init__(self, command, **kwargs):
                assert command[0] in ['xcodebuild', 'caffeinate']; calls.append(command)
                if command[0] == 'xcodebuild': kwargs['stdout'].write(b'Injected native stdout; not an actual run.\n')
            def wait(self, **kwargs): return 0
        module.subprocess = types.SimpleNamespace(Popen=Native, check_output=lambda *args, **kwargs: 'injected-commit\n', TimeoutExpired=subprocess.TimeoutExpired)
        def query(command):
            calls.append(command)
            if 'get_app_container' in command:
                (group / 'Lumen-retained-review-owner-events.json').write_text('{"schema":"injected","events":[]}')
                return {'command': command, 'pid': 424243, 'exit': 0, 'stdout': base64.b64encode(str(group).encode()).decode(), 'stderr': ''}
            if 'summary' in command:
                if fault == 'summary-query-raise': raise OSError('injected summary launch/communicate error')
                output = json.dumps({'passedTests': 1, 'failedTests': 0, 'skippedTests': 0}).encode()
            else:
                assert 'export' in command
                if fault == 'export-query-raise': raise OSError('injected export launch/communicate error')
                export = Path(command[command.index('--output-path') + 1]); export.mkdir()
                attachments = []
                for name, data in [('10-bad.png', b'injected first image'), ('20-later.png', b'injected later image'), ('readback.json', b'{}')]:
                    (export / name).write_bytes(data)
                    attachments.append({'exportedFileName': name, 'suggestedHumanReadableName': name})
                (export / 'manifest.json').write_text(json.dumps([{'testIdentifier': 'injected-test', 'attachments': attachments}]))
                output = b''
            return {'command': command, 'pid': 424244, 'exit': 0, 'stdout': base64.b64encode(output).decode(), 'stderr': ''}
        module.query = query
        old_argv = sys.argv; sys.argv = [str(actual), '--case', 'children']
        escaped = None
        try: module.main()
        except SystemExit as error: escaped = {'type': 'SystemExit', 'code': error.code}
        except BaseException as error: escaped = {'type': type(error).__name__, 'message': str(error)}
        finally: sys.argv = old_argv
        report_path = base / 'retained-owner-source258-children-r1-driver.json'
        report = json.loads(report_path.read_bytes())
        observed = {'fault': fault, 'escaped': escaped,
                    'summaryAttempted': any('summary' in cmd for cmd in calls),
                    'exportAttempted': any('export' in cmd for cmd in calls),
                    'terminalPersisted': report['status'] != 'RUNNING',
                    'retainedNames': [item['name'] for item in report.get('originals', [])],
                    'state': report, 'injectedCalls': calls}
        if fault == 'success':
            fixed = escaped == {'type': 'SystemExit', 'code': False} and report['errors'] == [] and set(observed['retainedNames']) == {'10-bad.png', '20-later.png', 'manifest.json', 'readback.json'}
        elif fault == 'summary-query-raise':
            fixed = observed['summaryAttempted'] and observed['exportAttempted'] and observed['terminalPersisted'] and bool(report['errors'])
        elif fault == 'export-query-raise':
            fixed = observed['summaryAttempted'] and observed['exportAttempted'] and observed['terminalPersisted'] and bool(report['errors'])
        else:
            fixed = observed['terminalPersisted'] and bool(report['errors']) and '20-later.png' in observed['retainedNames'] and 'readback.json' in observed['retainedNames']
        observed['correctRetention'] = fixed
        assert fixed is (not a.expect_defects), (fault, observed)
        return observed


for fault in ['success', 'summary-query-raise', 'export-query-raise', 'peer-copy-raise']: rows.append(trial(fault))
report = {'status': 'REPRODUCED four frozen driver defects' if a.expect_defects else 'PASS four actual-main injected retention cases',
          'driver': a.driver, 'driverBytes': actual.stat().st_size, 'driverSHA256': hashlib.sha256(actual.read_bytes()).hexdigest(),
          'count': len(rows), 'cases': rows, 'scope': 'Actual main and real temporary file retention; injected source/build/proof/provider/native/query functions and synthetic PID metadata. No native/source verification/build/compiled-pair acceptance.', 'checkedAt': time.time()}
target = B / a.output; assert not target.exists(); target.write_text(json.dumps(report, indent=2) + '\n')
print(report['status'], report['count'])
