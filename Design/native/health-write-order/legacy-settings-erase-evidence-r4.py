"""Bind unchanged strict erasure predicates to the explicit fresh context.

This adapter has no old-device fallback. Import reads only the declared context;
all ordinary native predicates remain the independently reviewed R2 functions.
"""
import importlib.util
import json
from pathlib import Path

BASE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('fresh_reset_parent', BASE / 'legacy-settings-erase-evidence-r2.py')
parent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parent)
context = json.loads((BASE / 'source224-reset-provider-context.json').read_text())
attempt = json.loads((BASE / 'source224-reset-provider-seed-r2-attempt.json').read_text())
assert attempt['status'] == 'PASS seeded exact 4992-byte synthetic input'
assert attempt['contextIntended'] == context and attempt['targetCreated'] is True
assert not any(attempt.get(key) for key in ['error', 'targetInspectionError', 'persistenceError'])
assert not (BASE / 'source224-reset-provider-seed-r2-emergency.json').exists()
assert attempt['actualTarget']['identity'] == context['identity']
assert attempt['actualTarget']['sha256'] == context['sha256'] and attempt['actualTarget']['bytes'] == 4992
DEVICE = '5C4C4A6C-4D9E-4181-8794-E3925C1A7EA7'
assert context['device'] == DEVICE and context['status'].startswith('PASS seeded one exact synthetic backup')
diagnostic = json.loads((BASE / context['freshDiagnostic']).read_text())
assert diagnostic['device'] == DEVICE and diagnostic['status'].startswith('PASS actual fresh-context')
assert diagnostic['diagnostic']['classification'] == 'approved-initial'
assert diagnostic['diagnostic']['credentialQueryOSStatus'] == -25300
h = parent.h
h.DEVICE = DEVICE


def provider():
    path = Path(context['seeded'])
    device_root = Path.home() / 'Library/Developer/CoreSimulator/Devices' / DEVICE
    assert path.is_relative_to(device_root)
    assert path.name == h.NAME
    facts = h.identity(path)
    data = h.read(path)
    assert facts == context['identity']
    assert len(data) == context['bytes'] == 4992
    assert h.sha(data) == context['sha256'] == '80d236abd21b33a3d012d3287a0606e699d53ddc18a9e4263a635cb899629078'
    canonical = BASE / ('health-photo-matrix-r1-' + h.NAME)
    assert data == h.read(canonical)
    return {'file': str(path), 'identity': facts, **h.row(data)}


h.provider = provider


def preflight(group, observation, started, sink):
    """Retain actual normal/observer guard bytes before validating them."""
    path = group / ('Lumen-legacy-reset-preflight-diagnostic-' + observation['runID'].lower()
                    + '-' + str(observation['pid']) + '.json')
    raw = h.read(path, 4096)
    sink.update(file=str(path), identity=h.identity(path), **h.row(raw))
    value = json.loads(raw)
    sink['value'] = value
    assert value['verificationProtocol'] == 'Lumen-legacy-reset-preflight-diagnostic-v1'
    assert value['runID'] == observation['runID'] and value['pid'] == observation['pid']
    assert value['at'] >= started and value['diagnosticOnly'] is False
    assert value['contextValid'] is True and value['guardApproved'] is True
    assert value['contextMode'] == observation['mode']
    initial = observation['mode'] == 'initial-fixture'
    flags = ['-health-legacy-reset-ui', '-health-legacy-reset-observer',
             '-health-legacy-reset-run', '-health-legacy-reset-diagnostic-only']
    assert value['knownFlagPresence'] == dict(zip(flags, [initial, not initial, True, False]))
    if initial:
        assert value['classification'] == 'approved-initial'
        assert value['localHealthConnected'] is False and value['credentialQueryPerformed'] is True
        assert value['credentialQueryOSStatus'] == -25300 and value['knownLegacyProviderKeysPresent'] == []
    else:
        assert value['classification'] == 'approved-observer' and value['credentialQueryPerformed'] is False
        assert 'credentialQueryOSStatus' not in value
    return value


# Re-export the exact parent functions. Their global h is this same patched
# module object, including selected()/receipt()/events()/container() calls.
for name in dir(parent):
    if not name.startswith('_'):
        globals()[name] = getattr(parent, name)


persistence = module('erasure_readonly_persistence', 'legacy-erasure-persistence-observation-r1.py')

def wait_preferences(observation, original, sink, persist):
    path = h.container('data') / 'Library/Preferences/com.dbakp.lumen.plist'
    persistence.wait(path, original, observation, sink, persist, h)
