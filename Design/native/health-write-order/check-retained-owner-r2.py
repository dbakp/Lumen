"""Mandatory fresh-source checker of one actual retained-owner native case."""
from pathlib import Path
import argparse, base64, gzip, hashlib, importlib.util, json, time, traceback

B = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', choices=['children', 'pending-back', 'sheet-dismiss'], required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('retained_driver', B / 'retained-owner-driver-r2.py')
    driver = importlib.util.module_from_spec(spec); spec.loader.exec_module(driver)
    protocol = driver.module('retained-owner-protocol-r1.py')
    prefix = 'retained-owner-source259-' + args.case + '-r1'
    target = B / (prefix + '-mandatory-audit.json'); assert not target.exists()
    result = {'status': 'FAILED', 'source': 'durable-source-r259.json', 'case': args.case,
              'prefix': prefix, 'startedAt': time.time()}
    try:
        result['sourceInputs'] = driver.verify_source()
        state = json.loads((B / (prefix + '-driver.json')).read_bytes())
        assert state['source'] == result['source'] and state['case'] == args.case and state['prefix'] == prefix
        evidence = driver.module('retained-owner-evidence-r1.py')
        current = evidence.preflight(B, evidence.SOURCE, driver.verify_source)
        assert evidence.validate_recorded(state, current, args.case, driver.RAW)
        assert evidence.validate_preflight_replay(state['preflightAfter'], current)
        assert state['status'] == 'NATIVE_FINISHED acceptance pending'
        assert state['nativeFinalization']['launched'] is True and state['nativeFinalization']['exit'] == 0
        assert type(state['nativeFinalization']['exit']) is int
        assert state['nativeFinalization']['errors'] == []
        assert state['originalFailures'] == []
        assert type(state['nativePID']) is int and state['nativePID'] > 0
        assert state['nativeFinalization']['pid'] == state['nativePID']
        assert type(state['nativeExit']) is int
        result['currentExecutionFacts'] = current
        expected_installed = ['xcrun', 'simctl', 'get_app_container', driver.DEVICE, 'com.dbakp.lumen', 'app']
        assert state['installedAppQuery']['command'] == expected_installed and state['installedAppQuery']['exit'] == 0
        result['installedAppQuery'] = driver.query(expected_installed)
        assert result['installedAppQuery']['exit'] == 0 and not result['installedAppQuery'].get('error')
        installed = Path(base64.b64decode(result['installedAppQuery']['stdout'], validate=True).decode().strip()) / 'Lumen'
        result['installedAppCurrent'] = evidence.file_fact(installed)
        assert result['installedAppCurrent'] == state['installedApp']
        assert state['installedApp']['sha256'] == current['app']['sha256'] and state['installedApp']['bytes'] == current['app']['bytes']
        assert state['nativeExit'] == 0 and state['errors'] == []
        assert state['physicalDeviceActions'] is False
        assert state['providerBefore'] == state['providerAfter'] == driver.provider()
        assert state['summaryQuery']['exit'] == state['exportQuery']['exit'] == 0
        bundle = driver.RAW / (state['stem'] + '.xcresult')
        assert state['summaryQuery']['command'] == ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle)]
        assert state['exportQuery']['command'] == ['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(bundle), '--output-path', str(driver.RAW / (state['stem'] + 'All'))]
        for name in ['summaryQuery', 'exportQuery', 'installedAppQuery']:
            acquired = state[name]
            assert type(acquired['pid']) is int and acquired['pid'] > 0
            assert type(acquired['exit']) is int and acquired['exit'] == 0 and not acquired.get('error')
            for stream in ['stdout', 'stderr']: base64.b64decode(acquired[stream], validate=True)
        assert state['originalManifest'] == prefix + '-original-manifest.json'
        assert state['trace']['file'] == prefix + '-trace.json'
        log = state['log']; assert log['file'] == prefix + '-native.log.gz'
        log_raw = gzip.decompress((B / log['file']).read_bytes())
        assert len(log_raw) == log['bytes'] and hashlib.sha256(log_raw).hexdigest() == log['sha256']
        summary = json.loads(base64.b64decode(state['summaryQuery']['stdout'], validate=True))
        assert [summary[key] for key in ['passedTests', 'failedTests', 'skippedTests']] == [1, 0, 0]
        assert all(type(summary[key]) is int for key in ['passedTests', 'failedTests', 'skippedTests'])
        for item in state['originals']:
            assert Path(item['file']).name == item['file']
            path = B / item['file']; assert not path.is_symlink()
            raw = path.read_bytes()
            assert len(raw) == item['bytes'] and hashlib.sha256(raw).hexdigest() == item['sha256']
        manifest = json.loads((B / state['originalManifest']).read_bytes())
        assert isinstance(manifest, list) and len(manifest) == 1
        assert manifest[0]['testIdentifier'] == 'LumenSmokeTests/' + protocol.CASES[args.case][0] + '()'
        attachments = manifest[0]['attachments']
        originals = {item['name']: item for item in state['originals']}
        assert len(originals) == len(state['originals'])
        assert set(originals) == {'manifest.json'} | {item['exportedFileName'] for item in attachments}
        expected = ['retained-owner-' + suffix for suffix in protocol.CASES[args.case][1]]
        pngs = [item for item in attachments if item['exportedFileName'].endswith('.png')]
        for name in expected:
            assert len([item for item in pngs if item['suggestedHumanReadableName'].startswith(name + '_')]) == 1, name
        readbacks = [item for item in attachments if item['suggestedHumanReadableName'].startswith('retained-owner-' +
            {'children': 'children', 'pending-back': 'pending', 'sheet-dismiss': 'sheet'}[args.case] + '-readback')]
        assert len(readbacks) == 1
        readback = json.loads((B / originals[readbacks[0]['exportedFileName']]['file']).read_bytes())
        fact = state['trace']; raw = (B / fact['file']).read_bytes()
        assert len(raw) == fact['bytes'] and hashlib.sha256(raw).hexdigest() == fact['sha256']
        result['protocol'] = protocol.validate(args.case, json.loads(raw), readback)
        result['originalCount'] = len(state['originals']); result['pngCount'] = len(pngs)
        result['status'] = 'SUPPORTED native trace/readback/export; original visual/root/critic review pending'
        result['scope'] = 'One actual case, sampled native screenshots and metadata trace. No global lifetime/continuous visibility/appearance/phone/full-goal acceptance.'
    except BaseException:
        result['error'] = traceback.format_exc()
    result['finishedAt'] = time.time()
    driver.write_new(target, result)
    print(json.dumps(result))
    raise SystemExit(not result['status'].startswith('SUPPORTED'))


if __name__ == '__main__': main()
