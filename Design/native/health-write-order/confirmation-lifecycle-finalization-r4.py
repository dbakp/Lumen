"""Finalize the actual reviewed lifecycle case and preserve malformed audit failures.

Command construction is pure. Execution is only through main; imports perform
no process queries, writes, app launches or cleanup.
"""
from pathlib import Path
import argparse
import base64
import gzip
import hashlib
import json
import re
import shutil
import subprocess
import time


def checker_command(base, plan, state, outcome):
    source, case_source = plan['source'], plan['caseSource']
    for name in [source, case_source]:
        assert re.fullmatch(r'durable-source-r[0-9]+\.json', name)
    assert case_source == state['source'] == outcome['source'] == state['preflight']['source']
    assert source == state['hostSource'] == state['hostSourceVerification']['source']
    build = plan['build']
    assert re.fullmatch(r'health-target-change-source[0-9]+-r[0-9]+-build\.json', build)
    assert build == state['build'] == outcome['build'] == state['preflight']['build']
    assert re.fullmatch(r'Source[0-9]+R[0-9]+', plan['nativeTrial'])
    assert plan['prefix'] == 'health-confirmation-notnow-data-' + plan['nativeTrial'].lower()
    assert plan['rawStem'] == 'HealthConfirmationNotNowData' + plan['nativeTrial']
    assert re.fullmatch(r'[A-Za-z0-9-]+', plan['checkerTrial'])
    command = state['command']
    assert command.count('-resultBundlePath') == 1
    assert command[command.index('-resultBundlePath') + 1] == str(
        Path('/tmp/LumenBatch44Checks') / (plan['rawStem'] + '.xcresult'))
    checker_match = re.fullmatch(r'check-confirmation-lifecycle-r([0-9]+)\.py', plan['checker'])
    assert checker_match and plan['checkerOutcomeProtocol'] == 'lifecycle-r' + checker_match.group(1)
    return ['python3', str(base / plan['checker']),
            plan['prefix'], '--checker-source', source, '--case-source', case_source,
            '--build', build, '--trial', plan['checkerTrial']]


def payload(raw):
    return {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(),
            'base64': base64.b64encode(raw).decode()}


def write_new(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', required=True)
    args = parser.parse_args()
    base = Path(__file__).resolve().parent
    assert Path(args.plan).name == args.plan
    plan = json.loads((base / args.plan).read_bytes())
    prefix = plan['prefix']
    assert re.fullmatch(r'[A-Za-z0-9-]+', prefix)
    state = json.loads((base / (prefix + '-driver-observations.json')).read_bytes())
    outcome = json.loads((base / (prefix + '-outcome.json')).read_bytes())
    command = checker_command(base, plan, state, outcome)
    report_path = base / (prefix + '-mandatory-checker-query.json')
    audit_path = base / (prefix + '-' + plan['checkerOutcomeProtocol'] + '-' + plan['checkerTrial'].lower() + '-outcome.json')
    assert not report_path.exists() and not audit_path.exists()
    assert shutil.disk_usage(base).free > 8 * 1024**3
    # Persist the coherent argv before invocation; never infer execution from an expected exit.
    write_new(base / (prefix + '-mandatory-checker-intended-command.json'),
              {'plan': args.plan, 'command': command, 'checkedAt': time.time()})
    proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = proc.communicate()
    stage_errors = []
    query = {'command': command, 'pid': proc.pid, 'exit': proc.returncode,
             'stdout': payload(stdout), 'stderr': payload(stderr), 'checkedAt': time.time()}
    try:
        write_new(report_path, query)
    except Exception as error:
        stage_errors.append({'stage': 'checker-query-persistence', 'type': type(error).__name__, 'message': str(error)})
    # Attempt durable child retention before interpreting output; a failed write is latched.
    coherent = False
    audit_observation = {'actualAuditCoherent': False, 'error': None, 'checkerQuery': query, 'stageErrors': stage_errors}
    try:
        with audit_path.open('rb') as stream:
            audit_raw = stream.read(8 * 1024**2 + 1)
        audit_observation['raw'] = payload(audit_raw)
        assert len(audit_raw) <= 8 * 1024**2, 'Audit exceeds bounded8MiB interpretation limit'
        audit = json.loads(audit_raw)
        assert isinstance(audit, dict), 'Checker audit must be an object'
        verification = audit.get('checkerSourceVerification')
        assert isinstance(verification, dict), 'Actual checker source verification required'
        coherent = bool(verification.get('source') == plan['source']
                        and audit.get('caseSource') == plan['caseSource']
                        and audit.get('checkerSource') == plan['source']
                        and audit.get('build') == plan['build'] and audit.get('prefix') == prefix
                        and audit.get('trial') == plan['checkerTrial'])
        assert coherent, 'Actual checker result must bind this reviewed case and source'
        audit_observation['actualAuditCoherent'] = True
    except Exception as error:
        audit_observation['error'] = {'type': type(error).__name__, 'message': str(error)}
    audit_observation['checkedAt'] = time.time()
    try:
        write_new(base / (prefix + '-mandatory-checker-audit-observation.json'), audit_observation)
    except Exception as error:
        stage_errors.append({'stage': 'audit-observation-persistence', 'type': type(error).__name__, 'message': str(error)})

    # Complete unfiltered acquisition also runs when the checker rejects the case.
    root = Path('/tmp/LumenBatch44Checks') / (plan['rawStem'] + 'All')
    assert not root.exists()
    export = ['xcrun', 'xcresulttool', 'export', 'attachments', '--path',
              str(root.parent / (plan['rawStem'] + '.xcresult')), '--output-path', str(root)]
    result = subprocess.run(export, capture_output=True)
    write_new(base / (prefix + '-all-original-export-query.json'),
              {'command': export, 'exit': result.returncode,
               'stdout': payload(result.stdout), 'stderr': payload(result.stderr), 'checkedAt': time.time()})
    assert result.returncode == 0
    manifest = (root / 'manifest.json').read_bytes()
    with (base / (prefix + '-all-original-manifest.json.gz')).open('xb') as stream:
        stream.write(gzip.compress(manifest, mtime=0))
    rows, other, kinds = [], {}, {}
    for path in sorted(root.rglob('*')):
        assert not path.is_symlink()
        if not path.is_file() or path == root / 'manifest.json':
            continue
        raw = path.read_bytes()
        kind = {'.png': 'png', '.json': 'json', '.mp4': 'video'}.get(path.suffix.lower(),
               'binary-plist' if raw.startswith(b'bplist') else 'text' if path.suffix.lower() in ['.txt', '.log', '.xml'] else 'other')
        fact = {'file': str(path.relative_to(root)), 'kind': kind,
                'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}
        if kind in ['png', 'json', 'video']:
            target = base / (prefix + '-' + path.name)
            if target.exists():
                assert target.read_bytes() == raw
            else:
                with target.open('xb') as stream:
                    stream.write(raw)
            fact['retained'] = target.name
        else:
            other[fact['file']] = payload(raw)
        rows.append(fact)
        kinds[kind] = kinds.get(kind, 0) + 1
    archive = json.dumps({'files': other}).encode()
    archive_name = prefix + '-all-other-originals.json.gz'
    with (base / archive_name).open('xb') as stream:
        stream.write(gzip.compress(archive, mtime=0))
    write_new(base / (prefix + '-all-originals.json'),
              {'status': 'All actual original bytes retained; no native acceptance',
               'count': len(rows), 'kinds': kinds, 'rows': rows, 'stageErrors': stage_errors,
               'completeManifest': {'file': prefix + '-all-original-manifest.json.gz',
                                    'bytes': len(manifest), 'sha256': hashlib.sha256(manifest).hexdigest()},
               'otherArchive': {'file': archive_name, 'decodedBytes': len(archive),
                                'decodedSHA256': hashlib.sha256(archive).hexdigest()},
               'scope': 'Original screenshots unreviewed; video byte-retained unplayed. No cleanup/reset.',
               'checkedAt': time.time()})
    assert not stage_errors, 'Collector persistence failed; evidence acquisition attempted'
    assert coherent, 'Actual checker must verify the current source, even for a failed case'
    expected = 0 if outcome['nativeExit'] == outcome['driverExit'] == 0 else 1
    assert proc.returncode == expected
    print(json.dumps({'checkerExit': proc.returncode, 'actualAuditCoherent': coherent,
                      'originals': len(rows), 'kinds': kinds}))


if __name__ == '__main__':
    main()
