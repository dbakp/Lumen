"""Retain actual mandatory checker completion before interpreting its audit."""
from pathlib import Path
import argparse, base64, json, subprocess, time, traceback

B = Path(__file__).resolve().parent


def checker_command(case):
    assert case in ['children', 'pending-back', 'sheet-dismiss']
    return ['python3', str(B / 'check-retained-owner-r1.py'), '--case', case]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--case', choices=['children', 'pending-back', 'sheet-dismiss'], required=True)
    args = p.parse_args(); prefix = 'retained-owner-source258-' + args.case + '-r1'
    output = B / (prefix + '-mandatory-checker-query.json')
    outcome = B / (prefix + '-finalization.json')
    assert not output.exists() and not outcome.exists()
    command = checker_command(args.case)
    child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = child.communicate()
    query = {'command': command, 'pid': child.pid, 'exit': child.returncode,
             'stdout': base64.b64encode(out).decode(), 'stderr': base64.b64encode(err).decode(), 'checkedAt': time.time()}
    # Persist completed child provenance before any audit interpretation.
    output.write_text(json.dumps(query, indent=2) + '\n')
    result = {'status': 'FAILED', 'source': 'durable-source-r258.json', 'case': args.case, 'query': output.name}
    try:
        path = B / (prefix + '-mandatory-audit.json')
        with path.open('rb') as stream: raw = stream.read(1024 * 1024 + 1)
        result['rawAuditBase64'] = base64.b64encode(raw).decode()
        assert len(raw) <= 1024 * 1024
        audit = json.loads(raw); assert isinstance(audit, dict)
        assert audit['source'] == result['source'] and audit['case'] == args.case and audit['prefix'] == prefix
        assert child.returncode == 0 and audit['status'].startswith('SUPPORTED')
        result['status'] = 'SUPPORTED mandatory checker completion; originals/root/critic/exact pending'
    except BaseException: result['error'] = traceback.format_exc()
    result['checkedAt'] = time.time(); outcome.write_text(json.dumps(result, indent=2) + '\n')
    print(result['status']); raise SystemExit(not result['status'].startswith('SUPPORTED'))


if __name__ == '__main__': main()
