"""Adversarial pure-protocol controls; these are not native evidence."""
from pathlib import Path
import copy, hashlib, importlib.util, json, uuid
B = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('retained_protocol', B / 'retained-owner-protocol-r1.py')
p = importlib.util.module_from_spec(spec); spec.loader.exec_module(p)
owners = [str(uuid.uuid4()).upper() for _ in range(2)]
operations = [str(uuid.uuid4()).upper() for _ in range(2)]
captures = [str(uuid.uuid4()).upper() for _ in range(2)]


def fixture(case):
    rows = []
    for i in range(2):
        def row(event, closed=False, metadata=False, operation=True):
            return {'event': event, 'sessionID': owners[i], 'operationID': operations[i] if operation else None,
                    'closed': closed, 'metadata': metadata}
        rows += [row('opened', operation=False), row('capture-started')]
        if case == 'pending-back' and i == 0:
            rows += [row('capture-held'), row('closed', True, operation=False),
                     row('capture-hold-cancelled', True), row('capture-cancelled', True)]
        else:
            rows += [row('capture-ready', metadata=True)]
            if i == 0 and case in ['children', 'sheet-dismiss']:
                rows += [row('records-read', metadata=True), row('photo-read', metadata=True)]
            rows += [row('closed', True, operation=False)]
    first = dict(session=owners[0], capture=captures[0], phase='pending' if case == 'pending-back' else 'ready', selected='')
    fresh = dict(session=owners[1], capture=captures[1], phase='ready', selected='')
    text = lambda v: ';'.join(k + '=' + v[k] for k in ['session', 'capture', 'phase', 'selected'])
    if case == 'children':
        readback = dict(first=first, selected=dict(first, selected='meals'), returned=dict(first, selected='meals'), fresh=fresh)
    else: readback = dict(old=text(first), fresh=text(fresh))
    return {'schema': 'Lumen-retained-review-owner-v1', 'events': rows}, readback


cases = []
def check(label, case, change=None):
    trace, readback = fixture(case)
    if change: change(trace, readback)
    try: p.validate(case, trace, readback); accepted = True
    except (AssertionError, ValueError, KeyError, TypeError): accepted = False
    passed = accepted == (change is None)
    cases.append({'name': label, 'case': case, 'accepted': accepted, 'passed': passed,
                  'trace': trace, 'readback': readback})
    assert passed, label


for case in p.CASES:
    check('valid isolated ' + case, case)
    check('reject duplicate owner ' + case, case, lambda t, r: t['events'].append(copy.deepcopy(t['events'][0])))
    check('reject missing close ' + case, case, lambda t, r: t['events'].pop())
    check('reject closed raw authority metadata ' + case, case, lambda t, r: t['events'][-1].update(metadata=True))
    check('reject Boolean-as-integer state ' + case, case, lambda t, r: t['events'][0].update(closed=0))
    check('reject reused capture operation ' + case, case, lambda t, r: [row.update(operationID=operations[0]) for row in t['events'] if row['operationID'] == operations[1]])
    check('reject unknown schema ' + case, case, lambda t, r: t.update(schema='old'))
    check('reject missing first capture ' + case, case, lambda t, r: t['events'].pop(1))
check('reject child loses selected choices', 'children', lambda t, r: r['returned'].update(selected=''))
check('reject child switches owner', 'children', lambda t, r: r['returned'].update(session=owners[1]))
check('reject reused UI capture', 'children', lambda t, r: r['fresh'].update(capture=captures[0]))
check('reject missing actual photo read', 'children', lambda t, r: t.update(events=[x for x in t['events'] if x['event'] != 'photo-read']))
check('reject pending late ready resurrection', 'pending-back', lambda t, r: t['events'].insert(5, dict(t['events'][1], event='capture-ready', metadata=True)))
check('reject missing cancelled worker terminal', 'pending-back', lambda t, r: t.update(events=[x for x in t['events'] if x['event'] != 'capture-cancelled']))
check('reject unlisted third-owner event', 'children', lambda t, r: t['events'].insert(1, dict(t['events'][1], sessionID=str(uuid.uuid4()).upper())))
check('reject selection before prior owner closes', 'children', lambda t, r: t['events'].insert(5, t['events'].pop(6)))
check('reject opened owner metadata', 'children', lambda t, r: t['events'][0].update(metadata=True))
check('reject capture starts closed', 'pending-back', lambda t, r: t['events'][1].update(closed=True))
raw = json.dumps(cases, indent=2).encode()
report = {'status': 'PASS isolated actual protocol controls', 'count': len(cases),
          'source': {'file': 'retained-owner-protocol-r1.py', 'bytes': (B / 'retained-owner-protocol-r1.py').stat().st_size,
                     'sha256': hashlib.sha256((B / 'retained-owner-protocol-r1.py').read_bytes()).hexdigest()},
          'cases': cases, 'scope': 'Synthetic adversarial inputs to the actual pure checker. No native/container/clock/UI acceptance.'}
target = B / 'source258-retained-protocol-controls-r2.json'; assert not target.exists()
target.write_text(json.dumps(report, indent=2) + '\n'); print(report['status'], report['count'])
