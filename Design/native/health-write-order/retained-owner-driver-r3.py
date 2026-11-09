"""Corrected retained-owner producer: independent acquisitions and exact execution facts.

Run after current source review/exact backup and current full app/test build/exact
backup. Each case must be reviewed and backed up before the next fixture reset.
"""
from pathlib import Path
import argparse, base64, gzip, hashlib, importlib.util, json, shutil, subprocess, time, traceback

B = Path(__file__).resolve().parent
R = B.parents[2]
DEVICE = '5C4C4A6C-4D9E-4181-8794-E3925C1A7EA7'
RAW = Path('/tmp/LumenBatch44Checks')
sha = lambda raw: hashlib.sha256(raw).hexdigest()


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), B / name)
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result); return result


def write_new(path, value):
    with path.open('x') as stream: json.dump(value, stream, indent=2); stream.write('\n')


def verify_source():
    manifest = json.loads((B / 'durable-source-r260.json').read_bytes())
    archive = json.loads(gzip.decompress((B / 'durable-source-r260.json.gz').read_bytes()))
    count = 0
    for group, key in [('files', 'files'), ('fixtureInputs', 'binaryFiles')]:
        assert set(manifest[group]) == set(archive[key])
        for name, fact in manifest[group].items():
            path = R / name; assert not path.is_symlink()
            raw = path.read_bytes()
            assert len(raw) == fact['bytes'] and sha(raw) == fact['sha256'], name
            assert raw == (archive[key][name].encode() if key == 'files' else base64.b64decode(archive[key][name], validate=True))
            count += 1
    return count


def query(command):
    p = None; out = err = b''
    result = {'command': command, 'pid': None, 'exit': None}
    try:
        p = subprocess.Popen(command, cwd=R, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        result['pid'] = p.pid
        out, err = p.communicate(timeout=90); result['exit'] = p.returncode
    except BaseException:
        result['error'] = traceback.format_exc()
        if p is not None:
            try: result['knownChildFinalization'] = finish_native(p)
            except BaseException: result['knownChildFinalizationError'] = traceback.format_exc()
            try: out, err = p.communicate(timeout=10); result['exit'] = p.returncode
            except BaseException: result['remainingStreamError'] = traceback.format_exc()
    result.update(stdout=base64.b64encode(out).decode(), stderr=base64.b64encode(err).decode())
    return result


def provider():
    context = json.loads((B / 'source224-reset-provider-context.json').read_bytes())
    assert context['device'] == DEVICE
    path = Path(context['seeded']); assert not path.is_symlink()
    raw = path.read_bytes(); facts = path.lstat()
    assert len(raw) == context['bytes'] and sha(raw) == context['sha256']
    for field, expected in context['identity'].items(): assert getattr(facts, field) == expected
    return {'bytes': len(raw), 'sha256': sha(raw), 'identity': context['identity']}


def finish_native(process):
    """Bounded known xcodebuild finalization; no claim about all child processes."""
    if process is None: return {'launched': False}
    result = {'launched': True, 'pid': process.pid, 'errors': []}
    for stage, seconds in [('natural-grace', 20), ('terminate', 20), ('kill', 20)]:
        try:
            if process.poll() is not None: result['exit'] = process.returncode; return result
            if stage == 'terminate': process.terminate()
            if stage == 'kill': process.kill()
            result['exit'] = process.wait(timeout=seconds); result['finishedBy'] = stage; return result
        except BaseException: result['errors'].append({'stage': stage, 'error': traceback.format_exc()})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', choices=['children', 'pending-back', 'sheet-dismiss'], required=True)
    args = parser.parse_args(); evidence = module('retained-owner-evidence-r2.py')
    prefix, stem = evidence.names(args.case)
    report = B / (prefix + '-driver.json'); emergency = B / (prefix + '-driver-emergency.json')
    result = RAW / (stem + '.xcresult'); log = RAW / (stem + '.log'); originals = RAW / (stem + 'All')
    assert not report.exists() and not emergency.exists()
    assert all(not path.exists() for path in [result, log, originals])
    assert shutil.disk_usage(R).free > 8 * 1024**3
    command = evidence.command(args.case, RAW)
    state = {'status': 'RUNNING', 'source': evidence.SOURCE, 'build': evidence.BUILD, 'case': args.case,
             'prefix': prefix, 'stem': stem, 'command': command, 'startedAt': time.time(),
             'physicalDeviceActions': False, 'errors': [], 'originals': [], 'originalFailures': []}
    process = None
    def fail(stage):
        state['errors'].append({'stage': stage, 'error': traceback.format_exc()})
    def persist(stage):
        try:
            pending = report.with_suffix('.json.pending')
            pending.write_text(json.dumps(state, indent=2) + '\n'); pending.replace(report)
            return True
        except BaseException:
            fail(stage + '-persistence'); state['status'] = 'FAILED persistence; no acceptance'
            try: emergency.write_text(json.dumps(state, indent=2) + '\n')
            except BaseException:
                # A total filesystem outage cannot be made durable by this caller.
                print('Emergency persistence failed: ' + traceback.format_exc(), flush=True)
            return False
    def acquisition(key, argv):
        try:
            acquired = query(argv)
            assert isinstance(acquired, dict)
            state[key] = acquired
            if acquired.get('exit') != 0 or acquired.get('error'):
                state['errors'].append({'stage': key, 'error': 'Actual query did not complete successfully', 'query': acquired})
        except BaseException:
            state[key] = {'command': argv, 'exit': None, 'error': traceback.format_exc()}; fail(key)
        persist(key)
    persist('initial')
    try:
        proof_name = evidence.proof_name(args.case)
        proof = json.loads((B / proof_name).read_bytes()); assert proof['source'] == evidence.SOURCE
        for ref in ['HEAD', 'origin/main']:
            assert subprocess.check_output(['git', 'rev-parse', ref], cwd=R, text=True).strip() == proof['commit']
        state['prerequisiteExactProof'] = proof_name
        state['preflight'] = evidence.preflight(B, evidence.SOURCE, verify_source)
        assert evidence.verify_checkpoint_facts(proof, state['preflight'], R)
        state['prerequisiteExactProofFact'] = evidence.file_fact(B / proof_name)
        state['providerBefore'] = provider(); persist('preflight')
        with log.open('xb') as out:
            process = subprocess.Popen(command, cwd=R, stdout=out, stderr=subprocess.STDOUT)
            state['nativePID'] = process.pid; persist('native-launched')
            try: subprocess.Popen(['caffeinate', '-i', '-w', str(process.pid)])
            except BaseException: fail('caffeinate'); persist('caffeinate-failure')
            state['nativeExit'] = process.wait(timeout=600); persist('native-completed')
        acquisition('containerQuery', ['xcrun', 'simctl', 'get_app_container', DEVICE, 'com.dbakp.lumen', 'group.com.dbakp.lumen'])
        assert state['containerQuery']['exit'] == 0
        group = Path(base64.b64decode(state['containerQuery']['stdout'], validate=True).decode().strip())
        trace = group / 'Lumen-retained-review-owner-events.json'
        assert not trace.is_symlink() and trace.stat().st_mtime >= state['startedAt']
        raw = trace.read_bytes(); assert len(raw) < 64 * 1024
        trace_name = prefix + '-trace.json'; (B / trace_name).write_bytes(raw)
        state['trace'] = {'file': trace_name, 'bytes': len(raw), 'sha256': sha(raw), 'raw': str(trace)}
        state['preflightAfter'] = evidence.preflight(B, evidence.SOURCE, verify_source)
        assert evidence.strict_json_equal(state['preflightAfter'], state['preflight'])
        state['providerAfter'] = provider(); assert evidence.strict_json_equal(state['providerAfter'], state['providerBefore'])
        acquisition('installedAppQuery', ['xcrun', 'simctl', 'get_app_container', DEVICE, 'com.dbakp.lumen', 'app'])
        assert state['installedAppQuery']['exit'] == 0
        installed = Path(base64.b64decode(state['installedAppQuery']['stdout'], validate=True).decode().strip()) / 'Lumen'
        state['installedApp'] = evidence.file_fact(installed)
        assert state['installedApp']['sha256'] == state['preflight']['app']['sha256']
        assert state['installedApp']['bytes'] == state['preflight']['app']['bytes']
        assert type(state['nativeExit']) is int and state['nativeExit'] == 0
    except BaseException: fail('native-or-preflight')
    finally:
        try:
            state['nativeFinalization'] = finish_native(process)
            if state['nativeFinalization'].get('errors') or (process is not None and state['nativeFinalization'].get('exit') != 0):
                state['errors'].append({'stage': 'known-native-finalization', 'facts': state['nativeFinalization']})
        except BaseException: fail('known-native-finalization')
        persist('known-native-finalization')
        try:
            raw = log.read_bytes(); (B / (prefix + '-native.log.gz')).write_bytes(gzip.compress(raw, mtime=0))
            state['log'] = {'file': prefix + '-native.log.gz', 'bytes': len(raw), 'sha256': sha(raw)}
        except BaseException: fail('log-retention')
        persist('log-retention')
        acquisition('summaryQuery', ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result)])
        acquisition('exportQuery', ['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(originals)])
        try:
            manifest = originals / 'manifest.json'; assert not manifest.is_symlink()
            parsed = json.loads(manifest.read_bytes()); assert isinstance(parsed, list)
            state['originalManifest'] = prefix + '-original-manifest.json'
        except BaseException: fail('manifest-interpretation')
        # Retain every available later peer even after exporter/manifest/peer errors.
        try:
            available = sorted(originals.rglob('*'))
        except BaseException: fail('original-inventory'); available = []
        for file in available:
            try:
                assert not file.is_symlink()
                if file.is_dir(): continue
                relative = file.relative_to(originals); assert len(relative.parts) == 1
                raw = file.read_bytes(); target = B / (prefix + '-original-' + file.name)
                if target.exists():
                    assert not target.is_symlink() and target.is_file() and target.read_bytes() == raw
                else: target.write_bytes(raw)
                state['originals'].append({'file': target.name, 'raw': str(file), 'name': file.name,
                                           'bytes': len(raw), 'sha256': sha(raw), 'individuallyOpened': False})
            except BaseException:
                state['originalFailures'].append({'raw': str(file), 'error': traceback.format_exc()}); fail('individual-original')
            persist('individual-original')
        state['status'] = 'NATIVE_FINISHED acceptance pending' if not state['errors'] else 'FAILED retention/native; no acceptance'
        state['finishedAt'] = time.time(); persist('terminal')
    print(json.dumps({'status': state['status'], 'nativeExit': state.get('nativeExit'), 'originals': len(state['originals'])}))
    raise SystemExit(bool(state['errors']))


if __name__ == '__main__': main()
