"""Actual query and finalizer callers with injected child results and real files."""
from pathlib import Path, PosixPath
import contextlib, hashlib, importlib.util, io, json, subprocess, sys, tempfile, time, types
B = Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), B / name)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value


query_cases = []
for fault in ['success', 'launch', 'communicate', 'nonzero']:
    d = load('retained-owner-driver-r2.py')
    class Child:
        pid = 424244
        def __init__(self, *args, **kwargs):
            if fault == 'launch': raise OSError('injected launch error')
            self.returncode = None; self.calls = 0
        def communicate(self, **kwargs):
            self.calls += 1
            if fault == 'communicate' and self.calls == 1: raise OSError('injected communicate error')
            self.returncode = 1 if fault == 'nonzero' else 0
            return b'exact injected stdout', b'exact injected stderr'
        def poll(self): return self.returncode
        def wait(self, **kwargs): self.returncode = 0; return 0
    d.subprocess = types.SimpleNamespace(Popen=Child, PIPE=subprocess.PIPE)
    result = d.query(['injected-query'])
    if fault == 'success': assert result['exit'] == 0 and 'error' not in result
    elif fault == 'launch': assert result['pid'] is None and result['exit'] is None and result['error']
    elif fault == 'communicate': assert result['pid'] == 424244 and result['error'] and result['knownChildFinalization']['exit'] == 0
    else: assert result['exit'] == 1
    query_cases.append({'fault': fault, 'result': result})

finalizer_cases = []
for fault in ['valid', 'missing', 'malformed', 'array', 'null', 'wrong-source', 'wrong-case', 'wrong-prefix', 'checker-nonzero', 'query-write', 'outcome-write']:
    with tempfile.TemporaryDirectory(prefix='lumen259-finalizer-injected-') as folder:
        class TestPath(PosixPath):
            def write_text(self, value, **kwargs):
                if fault == 'query-write' and self.name.endswith('-mandatory-checker-query.json'): raise OSError('injected query write failure')
                if fault == 'outcome-write' and self.name.endswith('-finalization.json'): raise OSError('injected outcome write failure')
                return super().write_text(value, **kwargs)
        f = load('retained-owner-finalization-r2.py'); f.B = TestPath(folder)
        prefix = 'retained-owner-source259-children-r1'
        audit = {'source': 'durable-source-r259.json', 'case': 'children', 'prefix': prefix, 'status': 'SUPPORTED injected'}
        if fault.startswith('wrong-'): audit[fault[6:]] = 'OTHER'
        raw = b'{malformed' if fault == 'malformed' else b'[]' if fault == 'array' else b'null' if fault == 'null' else json.dumps(audit).encode()
        if fault != 'missing': (f.B / (prefix + '-mandatory-audit.json')).write_bytes(raw)
        class Completed:
            pid = 424245
            returncode = 1 if fault == 'checker-nonzero' else 0
            def __init__(self, command, **kwargs): self.command = command
            def communicate(self): return b'injected checker stdout', b'injected checker stderr'
        f.subprocess = types.SimpleNamespace(Popen=Completed, PIPE=subprocess.PIPE)
        old = sys.argv; sys.argv = ['injected-finalizer', '--case', 'children']
        try:
            with contextlib.redirect_stdout(io.StringIO()): f.main()
        except SystemExit as error: code = error.code
        finally: sys.argv = old
        path = f.B / (prefix + ('-finalization-emergency.json' if fault == 'outcome-write' else '-finalization.json'))
        result = json.loads(path.read_bytes())
        assert (code == 0) == (fault == 'valid')
        assert result['actualCheckerQuery']['pid'] == 424245
        assert result['actualCheckerQuery']['stdout'] and result['actualCheckerQuery']['stderr']
        if fault != 'query-write': assert (f.B / (prefix + '-mandatory-checker-query.json')).exists()
        finalizer_cases.append({'fault': fault, 'exit': code, 'result': result})
report = {'status': 'PASS actual query/finalizer injected caller controls', 'queryCount': len(query_cases),
          'finalizerCount': len(finalizer_cases), 'queryCases': query_cases, 'finalizerCases': finalizer_cases,
          'sources': {name: {'bytes': (B / name).stat().st_size, 'sha256': hashlib.sha256((B / name).read_bytes()).hexdigest()}
                      for name in ['retained-owner-driver-r2.py', 'retained-owner-finalization-r2.py']},
          'scope': 'Actual query()/finalizer.main with named fake child processes and real temporary query/audit/outcome/emergency files. No native/current source verification/actual checker subprocess acceptance. Total filesystem outage remains unrecoverable.', 'checkedAt': time.time()}
target = B / 'source259-query-finalizer-controls-r1.json'; assert not target.exists(); target.write_text(json.dumps(report, indent=2) + '\n')
print(report['status'], report['queryCount'], report['finalizerCount'])
