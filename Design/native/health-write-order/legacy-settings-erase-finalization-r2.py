"""Latched terminal acceptance for synthetic erasure driver; no producer on import."""
import json
from pathlib import Path
import time
import traceback


def finalize(process, state, persist, outpath, loader, base, raw, stem, prefix, source, accept, shared, host_error=None,
             success_status="PASS actual native1/0/0 and strict host6boundaries; root/independent review pending"):
    error = host_error
    outcome = {'source': source, 'build': state['build'], 'case': state['case'], 'nativeExit': None,
               'hostError': error, 'driverExit': 1, 'status': 'INCOMPLETE finalization/retention pending',
               'physicalDeviceActions': False}

    def record():
        nonlocal error
        write_error = shared.record_outcome(outpath, outcome)
        error = error or write_error
        return write_error

    def safe_persist():
        nonlocal error
        try:
            persist()
        except BaseException:
            failure = traceback.format_exc()
            outcome.setdefault('finalizationPersistenceErrors', []).append(failure)
            error = error or failure
            outcome.update(status='FAILED state persistence; no acceptance', driverExit=1)
            record()

    record()  # Failure is latched before any finalizer/retainer call.
    native_code = None
    try:
        native_code = shared.finish_native(process, state, safe_persist)
    except BaseException:
        failure = traceback.format_exc(); error = error or failure
        state['nativeFinalizationError'] = failure
        outcome['nativeFinalizationError'] = failure
    state.update(nativeExit=native_code, finished=time.time(), hostError=error)
    safe_persist()
    outcome.update(nativeExit=native_code, hostError=error)
    record()
    retained, retention_error = shared.guarded_retain(loader, base, raw, stem, prefix, source, outcome, outpath)
    error = error or retention_error
    try:
        assert error is None and native_code == 0 and retained is not None
        assert not any(outcome.get(key) for key in ['outcomePersistenceErrors', 'finalizationPersistenceErrors',
            'nativeFinalizationError', 'retainerException', 'salvageException', 'emergencyOutcomePersistenceError'])
        assert not Path(str(outpath) + '.emergency.json').exists()
        accept(retained)
        outcome['status'] = success_status
    except BaseException:
        failure = traceback.format_exc(); error = error or failure
        outcome.update(status='FAILED or incomplete Settings erasure case; no acceptance', failure=failure)
    outcome.update(hostError=error, driverExit=0 if error is None else 1, finished=time.time())
    record()
    # record_outcome changes status/driverExit on its own write error too.
    if error is not None:
        outcome.update(driverExit=1, hostError=error)
        if outcome['status'].startswith('PASS'):
            outcome['status'] = 'FAILED terminal persistence; no acceptance'
    return outcome
