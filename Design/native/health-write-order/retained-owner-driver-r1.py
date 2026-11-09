"""Run one reviewed retained-owner native case and retain every exported original.

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
    manifest = json.loads((B / 'durable-source-r258.json').read_bytes())
    archive = json.loads(gzip.decompress((B / 'durable-source-r258.json.gz').read_bytes()))
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
    p = subprocess.Popen(command, cwd=R, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = p.communicate()
    return {'command': command, 'pid': p.pid, 'exit': p.returncode,
            'stdout': base64.b64encode(out).decode(), 'stderr': base64.b64encode(err).decode()}


def provider():
    context = json.loads((B / 'source224-reset-provider-context.json').read_bytes())
    assert context['device'] == DEVICE
    path = Path(context['seeded']); assert not path.is_symlink()
    raw = path.read_bytes(); facts = path.lstat()
    assert len(raw) == context['bytes'] and sha(raw) == context['sha256']
    for field, expected in context['identity'].items(): assert getattr(facts, field) == expected
    return {'bytes': len(raw), 'sha256': sha(raw), 'identity': context['identity']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', choices=['children', 'pending-back', 'sheet-dismiss'], required=True)
    a = parser.parse_args(); protocol = module('retained-owner-protocol-r1.py')
    prefix = 'retained-owner-source258-' + a.case + '-r1'
    stem = 'RetainedOwnerSource258' + a.case.replace('-', '').title() + 'R1'
    report = B / (prefix + '-driver.json'); assert not report.exists()
    result = RAW / (stem + '.xcresult'); log = RAW / (stem + '.log'); originals = RAW / (stem + 'All')
    assert all(not p.exists() for p in [result, log, originals])
    assert shutil.disk_usage(R).free > 8 * 1024**3
    count = verify_source()
    proof_name = {'children': 'source258-build-exact-github.json',
                  'pending-back': 'source258-children-exact-github.json',
                  'sheet-dismiss': 'source258-pending-back-exact-github.json'}[a.case]
    proof = json.loads((B / proof_name).read_bytes())
    assert proof['source'] == 'durable-source-r258.json'
    for ref in ['HEAD', 'origin/main']:
        assert subprocess.check_output(['git', 'rev-parse', ref], cwd=R, text=True).strip() == proof['commit']
    build = json.loads((B / 'health-target-change-source258-r1-build.json').read_bytes())
    assert build['source'] == 'durable-source-r258.json' and build['buildExit'] == 0
    app = Path('/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/Lumen.app/Lumen')
    test = Path(build['testBinary'])
    assert sha(app.read_bytes()) == build['sha256'] and app.stat().st_size == build['binaryBytes']
    assert sha(test.read_bytes()) == build['testBinarySHA256'] and test.stat().st_size == build['testBinaryBytes']
    command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
        '-destination', 'platform=iOS Simulator,id=' + DEVICE, '-derivedDataPath', '/tmp/LumenBatch37Simulator',
        '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
        '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
        '-only-testing:LumenUITests/LumenSmokeTests/' + protocol.CASES[a.case][0],
        '-resultBundlePath', str(result), 'test-without-building']
    state = {'status': 'RUNNING', 'source': 'durable-source-r258.json', 'case': a.case, 'prefix': prefix,
             'stem': stem, 'sourceInputs': count, 'build': 'health-target-change-source258-r1-build.json',
             'command': command, 'startedAt': time.time(), 'physicalDeviceActions': False, 'errors': [],
             'prerequisiteExactProof': proof_name, 'providerBefore': provider()}
    def persist(): report.write_text(json.dumps(state, indent=2) + '\n')
    persist()
    try:
        with log.open('xb') as out:
            process = subprocess.Popen(command, cwd=R, stdout=out, stderr=subprocess.STDOUT)
            state['nativePID'] = process.pid; persist()
            subprocess.Popen(['caffeinate', '-i', '-w', str(process.pid)])
            try: state['nativeExit'] = process.wait(timeout=600)
            except subprocess.TimeoutExpired:
                process.terminate()
                try: state['nativeExit'] = process.wait(timeout=20)
                except subprocess.TimeoutExpired: process.kill(); state['nativeExit'] = process.wait()
                raise
        container_query = query(['xcrun', 'simctl', 'get_app_container', DEVICE, 'com.dbakp.lumen', 'group.com.dbakp.lumen'])
        state['containerQuery'] = container_query; assert container_query['exit'] == 0
        group = Path(base64.b64decode(container_query['stdout']).decode().strip())
        trace = group / 'Lumen-retained-review-owner-events.json'
        assert not trace.is_symlink() and trace.stat().st_mtime >= state['startedAt']
        raw = trace.read_bytes(); assert len(raw) < 64 * 1024
        trace_name = prefix + '-trace.json'; (B / trace_name).write_bytes(raw)
        state['trace'] = {'file': trace_name, 'bytes': len(raw), 'sha256': sha(raw), 'raw': str(trace)}
        state['sourceInputsAfter'] = verify_source()
        state['providerAfter'] = provider()
        assert state['providerAfter'] == state['providerBefore']
        assert state['nativeExit'] == 0
    except BaseException:
        state['errors'].append({'stage': 'native', 'error': traceback.format_exc()})
    finally:
        # These acquisitions are independent even after a native/trace failure.
        try:
            raw = log.read_bytes(); (B / (prefix + '-native.log.gz')).write_bytes(gzip.compress(raw, mtime=0))
            state['log'] = {'file': prefix + '-native.log.gz', 'bytes': len(raw), 'sha256': sha(raw)}
        except BaseException: state['errors'].append({'stage': 'log', 'error': traceback.format_exc()})
        state['summaryQuery'] = query(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result)])
        state['exportQuery'] = query(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(originals)])
        try:
            assert state['exportQuery']['exit'] == 0
            manifest_path = originals / 'manifest.json'; assert not manifest_path.is_symlink()
            raw = manifest_path.read_bytes(); (B / (prefix + '-original-manifest.json')).write_bytes(raw)
            state['originalManifest'] = prefix + '-original-manifest.json'; state['originals'] = []
            # Inventory the complete unfiltered directory, retaining files the
            # test did not explicitly request too. Never silently omit videos.
            for file in sorted(originals.rglob('*')):
                assert not file.is_symlink()
                if file.is_dir(): continue
                relative = file.relative_to(originals)
                assert len(relative.parts) == 1
                target = B / (prefix + '-original-' + file.name)
                raw = file.read_bytes(); assert not target.exists(); target.write_bytes(raw)
                state['originals'].append({'file': target.name, 'raw': str(file), 'name': file.name,
                                           'bytes': len(raw), 'sha256': sha(raw), 'individuallyOpened': False})
        except BaseException: state['errors'].append({'stage': 'complete-original-export', 'error': traceback.format_exc()})
        state['status'] = 'NATIVE_FINISHED acceptance pending' if not state['errors'] else 'FAILED retention/native; no acceptance'
        state['finishedAt'] = time.time(); persist()
    print(json.dumps({'status': state['status'], 'nativeExit': state.get('nativeExit'), 'originals': len(state.get('originals', []))}))
    raise SystemExit(bool(state['errors']))


if __name__ == '__main__': main()
