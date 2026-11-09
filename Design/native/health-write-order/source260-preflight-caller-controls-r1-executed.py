"""Actual preflight body with historical context and source-verifier callback injection."""
from pathlib import Path
import copy, hashlib, importlib.util, json, shutil, tempfile, time
B = Path(__file__).resolve().parent
assert shutil.disk_usage(B).free > 8 * 1024**3
spec = importlib.util.spec_from_file_location('actual_preflight_evidence', B / 'retained-owner-evidence-r2.py')
e = importlib.util.module_from_spec(spec); spec.loader.exec_module(e)
receipt_name = 'health-target-change-source257-r1-build.json'; source_name = 'durable-source-r257.json'
receipt = json.loads((B / receipt_name).read_bytes()); manifest = json.loads((B / source_name).read_bytes())
archive = (B / (source_name + '.gz')).read_bytes()
old_source, old_build = e.SOURCE, e.BUILD; e.SOURCE, e.BUILD = source_name, receipt_name
cases = []
faults = ['valid-historical-context', 'source-verifier-error', 'missing-archive', 'wrong-test-path', 'wrong-app-digest']
faults += [key + ':' + kind for key in ['buildExit', 'sourceInputs', 'fixtureInputs', 'binaryBytes', 'testBinaryBytes'] for kind in ['float', 'Boolean', 'null']]
try:
    for fault in faults:
        with tempfile.TemporaryDirectory(prefix='lumen260-preflight-context-') as folder:
            base = Path(folder); current = copy.deepcopy(receipt)
            if ':' in fault:
                key, kind = fault.split(':'); current[key] = float(current[key]) if kind == 'float' else bool(current[key]) if kind == 'Boolean' else None
            elif fault == 'wrong-test-path': current['testBinary'] = '/tmp/not-the-verified-test'
            elif fault == 'wrong-app-digest': current['sha256'] = '0' * 64
            (base / source_name).write_text(json.dumps(manifest))
            (base / receipt_name).write_text(json.dumps(current))
            if fault != 'missing-archive': (base / (source_name + '.gz')).write_bytes(archive)
            callback_calls = []
            def source_verifier():
                callback_calls.append('injected historical context, no current257 source check')
                if fault == 'source-verifier-error': raise ValueError('injected verifier rejection')
                return len(manifest['files']) + len(manifest['fixtureInputs'])
            try: result = e.preflight(base, source_name, source_verifier); accepted = True; error = None
            except (AssertionError, ValueError, TypeError, FileNotFoundError) as failure:
                result = None; accepted = False; error = type(failure).__name__
            assert accepted == (fault == 'valid-historical-context'), fault
            cases.append({'fault': fault, 'accepted': accepted, 'errorType': error, 'sourceVerifierCalls': callback_calls, 'acquired': result})
finally: e.SOURCE, e.BUILD = old_source, old_build
report = {'status': 'PASS actual preflight body historical-context controls', 'count': len(cases), 'cases': cases,
          'source': {'file': 'retained-owner-evidence-r2.py', 'bytes': (B / 'retained-owner-evidence-r2.py').stat().st_size,
                     'sha256': hashlib.sha256((B / 'retained-owner-evidence-r2.py').read_bytes()).hexdigest()},
          'scope': 'Actual new preflight function reads genuine retained257 manifest/archive/receipt copies and matching historical cached app/test bytes. SOURCE/BUILD context and source-verification callback explicitly injected; no current257 whole-source audit or current260build/native acceptance. Real temp fixtures deleted; canonical inputs preserved.', 'checkedAt': time.time()}
target = B / 'source260-preflight-caller-controls-r1.json'; assert not target.exists(); target.write_text(json.dumps(report, indent=2) + '\n')
print(report['status'], report['count'])
