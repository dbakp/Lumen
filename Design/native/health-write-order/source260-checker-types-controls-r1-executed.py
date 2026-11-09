"""Actual mandatory-checker main with named source/native-query injections.

Historical genuine file facts are replayed separately by metadata controls.
Here draft259 identities and tiny fake images exercise orchestration only.
"""
from pathlib import Path
import argparse, base64, contextlib, copy, gzip, hashlib, importlib.util, io, json, sys, tempfile, time, types
B = Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), B / name)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value


p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--checker', default='check-retained-owner-r3.py')
p.add_argument('--driver', default='retained-owner-driver-r3.py')
p.add_argument('--evidence', default='retained-owner-evidence-r2.py')
p.add_argument('--output', required=True)
p.add_argument('--expect-type-defects', action='store_true')
args = p.parse_args()
for name in [args.checker, args.driver, args.evidence, args.output]: assert Path(name).name == name
e = load(args.evidence)
metadata = json.loads((B / 'source259-retained-metadata-controls-r2.json').read_bytes())
draft = copy.deepcopy(metadata['historicalGenuineMetadata']); draft.update(source=e.SOURCE, build=e.BUILD)
for key, name in [('manifest', e.SOURCE), ('archive', e.SOURCE + '.gz'), ('receipt', e.BUILD)]: draft[key]['path'] = str(B / name)
protocol_fixture = json.loads((B / 'source258-retained-protocol-controls-r2.json').read_bytes())['cases'][0]
rows = []
known_type_misses = {'installed-identity-bool', 'installed-identity-float', 'provider-before-bool', 'provider-after-float',
    'final-pid-float', 'log-bytes-float', 'log-bytes-bool', 'original-bytes-float', 'original-bytes-bool', 'empty-original-bytes-bool', 'trace-bytes-float'}


def trial(fault):
    with tempfile.TemporaryDirectory(prefix='lumen259-checker-caller-') as folder:
        base = Path(folder); prefix, stem = e.names('children'); raw_root = Path('/tmp/LumenBatch44Checks')
        for name in [args.driver, 'retained-owner-protocol-r1.py', args.evidence]:
            (base / name).write_bytes((B / name).read_bytes())
        attachments = []; originals = []
        def retain(name, raw):
            file = prefix + '-original-' + name; (base / file).write_bytes(raw)
            originals.append({'name': name, 'file': file, 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()})
        protocol = load('retained-owner-protocol-r1.py')
        for i, suffix in enumerate(protocol.CASES['children'][1]):
            name = 'image-' + str(i) + '.png'; retain(name, b'Explicit synthetic image bytes, not a PNG.')
            attachments.append({'exportedFileName': name, 'suggestedHumanReadableName': 'retained-owner-' + suffix + '_0_control.png'})
        retain('readback.json', json.dumps(protocol_fixture['readback']).encode())
        attachments.append({'exportedFileName': 'readback.json', 'suggestedHumanReadableName': 'retained-owner-children-readback_0.json'})
        for name, data in [('diagnostic-one.txt', b'X'), ('diagnostic-empty.txt', b'')]:
            retain(name, data); attachments.append({'exportedFileName': name, 'suggestedHumanReadableName': name})
        retain('manifest.json', json.dumps([{'testIdentifier': 'LumenSmokeTests/testHealthRetainedReviewOwnerChildren()', 'attachments': attachments}]).encode())
        trace = json.dumps(protocol_fixture['trace']).encode(); (base / (prefix + '-trace.json')).write_bytes(trace)
        log = b'X'; (base / (prefix + '-native.log.gz')).write_bytes(gzip.compress(log, mtime=0))
        def query(command, payload=b''):
            return {'command': command, 'pid': 424243, 'exit': 0, 'stdout': base64.b64encode(payload).decode(), 'stderr': ''}
        installed_command = ['xcrun', 'simctl', 'get_app_container', e.DEVICE, 'com.dbakp.lumen', 'app']
        installed_query = query(installed_command, str(e.APP.parent).encode())
        provider = {'bytes': 4992, 'sha256': 'injected provider', 'identity': {'st_nlink': 1}}
        proof_name = e.proof_name('children') if hasattr(e, 'proof_name') else 'source259-build-exact-github.json'
        (base / proof_name).write_text(json.dumps({'source': e.SOURCE, 'commit': 'injected-commit', 'proofs': []}))
        state = {'source': e.SOURCE, 'build': e.BUILD, 'case': 'children', 'prefix': prefix, 'stem': stem,
            'command': e.command('children', raw_root), 'preflight': copy.deepcopy(draft), 'preflightAfter': copy.deepcopy(draft),
            'status': 'NATIVE_FINISHED acceptance pending', 'nativeExit': 0, 'nativePID': 424242,
            'nativeFinalization': {'launched': True, 'pid': 424242, 'exit': 0, 'errors': []},
            'errors': [], 'originalFailures': [], 'providerBefore': copy.deepcopy(provider), 'providerAfter': copy.deepcopy(provider),
            'prerequisiteExactProof': proof_name, 'prerequisiteExactProofFact': e.file_fact(base / proof_name),
            'physicalDeviceActions': False, 'installedAppQuery': installed_query, 'installedApp': e.file_fact(e.APP),
            'summaryQuery': query(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(raw_root / (stem + '.xcresult'))], json.dumps({'passedTests': 1, 'failedTests': 0, 'skippedTests': 0}).encode()),
            'exportQuery': query(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(raw_root / (stem + '.xcresult')), '--output-path', str(raw_root / (stem + 'All'))]),
            'originals': originals, 'originalManifest': prefix + '-original-manifest.json',
            'trace': {'file': prefix + '-trace.json', 'bytes': len(trace), 'sha256': hashlib.sha256(trace).hexdigest()},
            'log': {'file': prefix + '-native.log.gz', 'bytes': len(log), 'sha256': hashlib.sha256(log).hexdigest()}}
        if fault == 'wrong-source': state['source'] = 'durable-source-r258.json'
        elif fault == 'wrong-build': state['build'] = 'other.json'
        elif fault == 'wrong-device': state['command'][state['command'].index('-destination') + 1] = 'id=OTHER'
        elif fault == 'wrong-only-test': state['command'][-4] = '-only-testing:OTHER'
        elif fault == 'wrong-summary-path': state['summaryQuery']['command'][-1] = '/tmp/other.xcresult'
        elif fault == 'null-query-pid': state['exportQuery']['pid'] = None
        elif fault == 'native-exit-Boolean': state['nativeExit'] = False
        elif fault == 'final-exit-Boolean': state['nativeFinalization']['exit'] = False
        elif fault == 'summary-count-Boolean': state['summaryQuery']['stdout'] = base64.b64encode(b'{"passedTests":1,"failedTests":false,"skippedTests":0}').decode()
        elif fault == 'null-manifest-metadata': state['preflight']['manifest'] = None
        elif fault == 'wrong-app-digest': state['preflight']['app']['sha256'] = '0' * 64
        elif fault == 'wrong-test-path': state['preflight']['test']['path'] = '/tmp/OTHER'
        elif fault == 'wrong-archive-bytes': state['preflight']['archive']['bytes'] += 1
        elif fault == 'after-Boolean-identity': state['preflightAfter']['receipt']['identity']['st_nlink'] = True
        elif fault == 'installed-digest': state['installedApp']['sha256'] = '0' * 64
        elif fault == 'trace-digest': state['trace']['sha256'] = '0' * 64
        elif fault == 'original-digest': state['originals'][0]['sha256'] = '0' * 64
        elif fault == 'wrong-manifest-path': state['originalManifest'] = '../other.json'
        elif fault == 'log-digest': state['log']['sha256'] = '0' * 64
        elif fault == 'not-terminal': state['status'] = 'RUNNING'
        elif fault == 'installed-identity-bool': state['installedApp']['identity']['st_nlink'] = True
        elif fault == 'installed-identity-float': state['installedApp']['identity']['st_nlink'] = 1.0
        elif fault == 'provider-before-bool': state['providerBefore']['identity']['st_nlink'] = True
        elif fault == 'provider-after-float': state['providerAfter']['identity']['st_nlink'] = 1.0
        elif fault == 'final-pid-float': state['nativeFinalization']['pid'] = 424242.0
        elif fault == 'final-pid-bool': state['nativeFinalization']['pid'] = True
        elif fault == 'log-bytes-float': state['log']['bytes'] = 1.0
        elif fault == 'log-bytes-bool': state['log']['bytes'] = True
        elif fault == 'original-bytes-float': next(row for row in state['originals'] if row['name'] == 'diagnostic-one.txt')['bytes'] = 1.0
        elif fault == 'original-bytes-bool': next(row for row in state['originals'] if row['name'] == 'diagnostic-one.txt')['bytes'] = True
        elif fault == 'empty-original-bytes-bool': next(row for row in state['originals'] if row['name'] == 'diagnostic-empty.txt')['bytes'] = False
        elif fault == 'trace-bytes-float': state['trace']['bytes'] = float(state['trace']['bytes'])
        (base / (prefix + '-driver.json')).write_text(json.dumps(state))
        checker = load(args.checker); checker.B = base
        real_spec = importlib.util.spec_from_file_location
        def injected_spec(name, path):
            spec = real_spec(name, path); original = spec.loader
            class Loader:
                def create_module(self, spec): return original.create_module(spec)
                def exec_module(self, driver):
                    original.exec_module(driver); driver.B = base; driver.RAW = raw_root
                    driver.verify_source = lambda: draft['inputCount']
                    driver.provider = lambda: copy.deepcopy(provider)
                    driver.subprocess = types.SimpleNamespace(check_output=lambda *a, **k: 'injected-commit\n')
                    driver.query = lambda argv: copy.deepcopy(installed_query)
                    actual_module = driver.module
                    def injected_module(filename):
                        value = actual_module(filename)
                        if filename == args.evidence:
                            value.preflight = lambda *args: copy.deepcopy(draft)
                            if hasattr(value, 'verify_checkpoint_facts'): value.verify_checkpoint_facts = lambda *args: True
                        return value
                    driver.module = injected_module
            spec.loader = Loader(); return spec
        checker.importlib = types.SimpleNamespace(util=types.SimpleNamespace(spec_from_file_location=injected_spec, module_from_spec=importlib.util.module_from_spec))
        old = sys.argv; sys.argv = ['injected-checker', '--case', 'children']; stdout = io.StringIO()
        try:
            with contextlib.redirect_stdout(stdout): checker.main()
        except SystemExit as error: code = error.code
        finally: sys.argv = old
        audit = json.loads((base / (prefix + '-mandatory-audit.json')).read_bytes())
        accepted = code == 0 and audit['status'].startswith('SUPPORTED')
        assert accepted == (fault == 'valid-injected' or (args.expect_type_defects and fault in known_type_misses)), (fault, audit)
        return {'fault': fault, 'exit': code, 'accepted': accepted, 'audit': audit}


faults = ['valid-injected', 'wrong-source', 'wrong-build', 'wrong-device', 'wrong-only-test', 'wrong-summary-path', 'null-query-pid',
          'native-exit-Boolean', 'final-exit-Boolean', 'summary-count-Boolean', 'null-manifest-metadata', 'wrong-app-digest', 'wrong-test-path',
          'wrong-archive-bytes', 'after-Boolean-identity', 'installed-digest', 'trace-digest', 'original-digest', 'wrong-manifest-path', 'log-digest', 'not-terminal']
faults += sorted(known_type_misses) + ['final-pid-bool']
for fault in faults: rows.append(trial(fault))
report = {'status': 'REPRODUCED typed-family checker defects' if args.expect_type_defects else 'PASS actual mandatory-checker main typed-family controls', 'count': len(rows), 'cases': rows,
          'sources': {name: {'bytes': (B / name).stat().st_size, 'sha256': hashlib.sha256((B / name).read_bytes()).hexdigest()}
                      for name in [args.checker, args.driver, args.evidence, 'retained-owner-protocol-r1.py']},
          'scope': 'Actual checker.main/file/trace/readback validation with named injected source verification, draft preflight/proof/Git/provider/installed endpoints. Tiny synthetic non-PNG bytes and legitimate empty diagnostic peer. No native/current260build/pixel/source-preflight acceptance. Generic genuine historical receipt/Git facts are separately tested.', 'checkedAt': time.time()}
target = B / args.output; assert not target.exists(); target.write_text(json.dumps(report, indent=2) + '\n')
print(report['status'], report['count'])
