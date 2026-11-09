"""Pure validation of actual retained-review trace and native readback."""
import uuid

CASES = {
    'children': ('testHealthRetainedReviewOwnerChildren', [
        'ready', 'selected', 'photo', 'returned', 'confirmation', 'parent', 'fresh', 'recovered', 'final-parent']),
    'pending-back': ('testHealthRetainedReviewOwnerPendingBack', [
        'pending', 'pending-parent', 'pending-fresh', 'pending-final-parent']),
    'sheet-dismiss': ('testHealthRetainedReviewOwnerSheetDismiss', [
        'sheet-ready', 'sheet-photo', 'sheet-dismissed', 'sheet-fresh', 'sheet-final-parent']),
}


def ui_state(value):
    assert isinstance(value, str)
    fields = value.split(';')
    assert len(fields) == 4 and all('=' in field for field in fields)
    pairs = [field.split('=', 1) for field in fields]
    assert len({key for key, _ in pairs}) == 4
    result = dict(pairs)
    assert set(result) == {'session', 'capture', 'phase', 'selected'}
    for field in ['session', 'capture']:
        assert str(uuid.UUID(result[field])).upper() == result[field]
    assert result['phase'] in ['pending', 'ready']
    assert result['selected'] in ['', 'meals']
    return result


def validate(case, trace, readback):
    assert case in CASES and isinstance(trace, dict)
    assert set(trace) == {'schema', 'events'} and trace['schema'] == 'Lumen-retained-review-owner-v1'
    rows = trace['events']
    assert isinstance(rows, list) and rows
    allowed = {'opened', 'capture-started', 'capture-ready', 'capture-cancelled', 'capture-failed',
               'capture-held', 'capture-hold-cancelled', 'records-read', 'photo-read', 'closed'}
    for row in rows:
        assert isinstance(row, dict) and set(row) == {'event', 'sessionID', 'operationID', 'closed', 'metadata'}
        assert row['event'] in allowed
        assert type(row['closed']) is bool and type(row['metadata']) is bool
        assert str(uuid.UUID(row['sessionID'])).upper() == row['sessionID']
        if row['operationID'] is not None:
            assert str(uuid.UUID(row['operationID'])).upper() == row['operationID']
        assert not (row['closed'] and row['metadata'])
    owners = [row['sessionID'] for row in rows if row['event'] == 'opened']
    assert len(owners) == 2 and len(set(owners)) == 2
    assert {row['sessionID'] for row in rows} == set(owners)
    assert next(i for i, row in enumerate(rows) if row['sessionID'] == owners[0] and row['event'] == 'closed') < next(i for i, row in enumerate(rows) if row['sessionID'] == owners[1] and row['event'] == 'opened')
    for row in rows:
        if row['event'] in ['opened', 'closed']: assert row['operationID'] is None
        if row['event'] in ['opened', 'capture-started', 'capture-held']:
            assert row['closed'] is False and row['metadata'] is False
    if case == 'children':
        assert set(readback) == {'first', 'selected', 'returned', 'fresh'}
        for state in readback.values():
            assert ui_state(';'.join(key + '=' + state[key] for key in ['session', 'capture', 'phase', 'selected'])) == state
        old, fresh = readback['first'], readback['fresh']
        assert readback['returned'] == readback['selected']
        assert readback['selected'] == dict(old, selected='meals')
    else:
        assert set(readback) == {'old', 'fresh'}
        old, fresh = ui_state(readback['old']), ui_state(readback['fresh'])
    assert old['session'] == owners[0] and fresh['session'] == owners[1]
    assert old['capture'] != fresh['capture'] and old['selected'] == fresh['selected'] == ''
    assert old['phase'] == ('pending' if case == 'pending-back' else 'ready') and fresh['phase'] == 'ready'
    operations = []
    for index, owner in enumerate(owners):
        entries = [row for row in rows if row['sessionID'] == owner]
        events = [row['event'] for row in entries]
        assert events[0] == 'opened' and events.count('opened') == events.count('closed') == 1
        starts = [row for row in entries if row['event'] == 'capture-started']
        assert len(starts) == 1 and starts[0]['operationID'] is not None
        operations.append(starts[0]['operationID'])
        closed = next(row for row in entries if row['event'] == 'closed')
        assert closed['closed'] is True and closed['metadata'] is False
        assert 'capture-failed' not in events
        if case == 'pending-back' and index == 0:
            assert 'capture-ready' not in events
            assert events.count('capture-held') == events.count('capture-hold-cancelled') == events.count('capture-cancelled') == 1
            assert events.index('capture-started') < events.index('capture-held') < events.index('capture-hold-cancelled') < events.index('capture-cancelled')
            terminal = next(row for row in entries if row['event'] == 'capture-cancelled')
            assert terminal['closed'] is True and terminal['metadata'] is False
        else:
            assert events.count('capture-ready') == 1 and 'capture-cancelled' not in events
            assert events.index('capture-started') < events.index('capture-ready') < events.index('closed')
            ready = next(row for row in entries if row['event'] == 'capture-ready')
            assert ready['metadata'] is True and ready['closed'] is False
        for row in entries:
            if row['event'].startswith('capture-'):
                assert row['operationID'] == starts[0]['operationID']
            if row['event'] in ['records-read', 'photo-read']:
                assert row['metadata'] is True and row['closed'] is False
                assert events.index('capture-ready') < events.index(row['event']) < events.index('closed')
        if case in ['children', 'sheet-dismiss'] and index == 0:
            assert 'records-read' in events and 'photo-read' in events
    assert len(set(operations)) == 2
    return {'owners': owners, 'captureOperations': operations, 'eventCount': len(rows),
            'scope': 'Actual trace plus UI readback consistency; no continuous visibility, reference-release or global descriptor claim.'}
