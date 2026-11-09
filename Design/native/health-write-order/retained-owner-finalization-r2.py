"""Retain actual mandatory checker completion before interpreting its audit."""
from pathlib import Path
import argparse, base64, json, subprocess, time, traceback

B = Path(__file__).resolve().parent


def checker_command(case):
    assert case in ['children', 'pending-back', 'sheet-dismiss']
    return ['python3', str(B / 'check-retained-owner-r2.py'), '--case', case]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--case', choices=['children', 'pending-back', 'sheet-dismiss'], required=True)
    args = p.parse_args(); prefix = 'retained-owner-source259-' + args.case + '-r1'
    output = B / (prefix + '-mandatory-checker-query.json')
    outcome = B / (prefix + '-finalization.json')
    assert not output.exists() and not outcome.exists() and not (B / (prefix + '-finalization-emergency.json')).exists()
    command = checker_command(args.case)
    child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = child.communicate()
    query = {'command': command, 'pid': child.pid, 'exit': child.returncode,
             'stdout': base64.b64encode(out).decode(), 'stderr': base64.b64encode(err).decode(), 'checkedAt': time.time()}
    # Retain completed child provenance before interpretation. If the primary
    # query write fails, the outcome still carries exact query bytes and error.
    result = {'status': 'FAILED', 'source': 'durable-source-r259.json', 'case': args.case,
              'query': output.name, 'actualCheckerQuery': query, 'errors': []}
    try: output.write_text(json.dumps(query, indent=2) + '\n')
    except BaseException: result['errors'].append({'stage': 'query-persistence', 'error': traceback.format_exc()})
    try:
        path = B / (prefix + '-mandatory-audit.json')
        with path.open('rb') as stream: raw = stream.read(1024 * 1024 + 1)
        result['rawAuditBase64'] = base64.b64encode(raw).decode()
        assert len(raw) <= 1024 * 1024
        audit = json.loads(raw); assert isinstance(audit, dict)
        assert audit['source'] == result['source'] and audit['case'] == args.case and audit['prefix'] == prefix
        assert child.returncode == 0 and audit['status'].startswith('SUPPORTED')
        assert result['errors'] == []
        result['status'] = 'SUPPORTED mandatory checker completion; originals/root/critic/exact pending'
    except BaseException: result['error'] = traceback.format_exc()
    result['checkedAt'] = time.time()
    try: outcome.write_text(json.dumps(result, indent=2) + '\n')
    except BaseException:
        result['status'] = 'FAILED outcome persistence; no acceptance'
        result['errors'].append({'stage': 'outcome-persistence', 'error': traceback.format_exc()})
        emergency = B / (prefix + '-finalization-emergency.json')
        try: emergency.write_text(json.dumps(result, indent=2) + '\n')
        except BaseException: print('Emergency outcome persistence failed: ' + traceback.format_exc(), flush=True)
    print(result['status']); raise SystemExit(not result['status'].startswith('SUPPORTED'))


if __name__ == '__main__': main()
