"""Shared immutable input validation for offline model evaluation tools."""
import hashlib
import json
from pathlib import Path

MANIFEST = Path(__file__).resolve().parents[2]/'Design/native/retrieval-quality/medembed-source.json'

def read_pin():
    value = json.loads(MANIFEST.read_text())
    assert value['repository'] == 'abhinand/MedEmbed-small-v0.1'
    assert value['revision'] == '40a5850d046cfdb56154e332b4d7099b63e8d50e'
    return value

def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        while block := stream.read(1_048_576):
            result.update(block)
    return result.hexdigest()

def verify_source(source):
    expected = read_pin()
    assert source.is_dir() and not source.is_symlink()
    assert json.loads((source/'provenance.json').read_text()) == expected
    allowed = {x['path'] for x in expected['files']} | {'provenance.json','source-api.json'}
    for path in source.rglob('*'):
        assert not path.is_symlink()
        if path.is_file():
            assert str(path.relative_to(source)) in allowed, str(path)
    for asset in expected['files']:
        path = source/asset['path']
        assert path.is_file() and path.stat().st_size == asset['bytes']
        assert digest(path) == asset['sha256'], asset['path']
    return expected
