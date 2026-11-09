"""Mandatory fresh-source checker of one actual retained-owner native case."""
from pathlib import Path
import argparse, base64, hashlib, importlib.util, json, time, traceback

B = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', choices=['children', 'pending-back', 'sheet-dismiss'], required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('retained_driver', B / 'retained-owner-driver-r1.py')
    driver = importlib.util.module_from_spec(spec); spec.loader.exec_module(driver)
    protocol = driver.module('retained-owner-protocol-r1.py')
    prefix = 'retained-owner-source258-' + args.case + '-r1'
    target = B / (prefix + '-mandatory-audit.json'); assert not target.exists()
    result = {'status': 'FAILED', 'source': 'durable-source-r258.json', 'case': args.case,
              'prefix': prefix, 'startedAt': time.time()}
    try:
        result['sourceInputs'] = driver.verify_source()
        state = json.loads((B / (prefix + '-driver.json')).read_bytes())
        assert state['source'] == result['source'] and state['case'] == args.case and state['prefix'] == prefix
        assert state['nativeExit'] == 0 and state['errors'] == []
        assert state['physicalDeviceActions'] is False
        assert state['providerBefore'] == state['providerAfter'] == driver.provider()
        assert state['summaryQuery']['exit'] == state['exportQuery']['exit'] == 0
        summary = json.loads(base64.b64decode(state['summaryQuery']['stdout'], validate=True))
        assert [summary[key] for key in ['passedTests', 'failedTests', 'skippedTests']] == [1, 0, 0]
        assert type(summary['passedTests']) is int
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
