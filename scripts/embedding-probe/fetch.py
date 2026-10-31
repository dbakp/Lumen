"""Fetch only the public, immutable files pinned by the checked-in manifest.

Usage: python fetch.py MANIFEST DESTINATION
No account token, question or Library data is used. Existing mismatched files and
symlinked paths are refused; a failed transfer removes only its own partial file.
"""
import hashlib
import json
import os
import shutil
import sys
import urllib.request
import uuid
from pathlib import Path
from pin import read_pin, digest as file_digest
manifest_path, root = map(Path, sys.argv[1:])
manifest = json.loads(manifest_path.read_text())
assert manifest == read_pin()
assert manifest['repository'] == 'abhinand/MedEmbed-small-v0.1'
assert manifest['revision'] == '40a5850d046cfdb56154e332b4d7099b63e8d50e'
allowed = {'config.json','config_sentence_transformers.json','modules.json','sentence_bert_config.json','special_tokens_map.json','tokenizer.json','tokenizer_config.json','vocab.txt','1_Pooling/config.json','README.md','model.safetensors'}
assert {x['path'] for x in manifest['files']} == allowed and len(manifest['files']) == len(allowed)
assert sum(x['bytes'] for x in manifest['files']) <= 135_000_000
assert not root.is_symlink()
root.mkdir(parents=True, exist_ok=True)
missing = sum(x['bytes'] for x in manifest['files'] if not (root/x['path']).exists())
assert missing == 0 or shutil.disk_usage(root).free >= missing + 32_000_000
for asset in manifest['files']:
    target = root/asset['path']
    assert not target.is_symlink() and not target.parent.is_symlink()
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        assert target.is_file() and target.stat().st_size == asset['bytes'] and file_digest(target) == asset['sha256'], str(target)
        continue
    stage = target.with_name(target.name+'.partial-'+str(uuid.uuid4()))
    url = 'https://huggingface.co/'+manifest['repository']+'/resolve/'+manifest['revision']+'/'+asset['path']
    size, digest = 0, hashlib.sha256()
    try:
        with urllib.request.urlopen(url,timeout=60) as response, stage.open('xb') as output:
            while block := response.read(1_048_576):
                size += len(block)
                assert size <= asset['bytes']
                digest.update(block)
                output.write(block)
        assert size == asset['bytes'] and digest.hexdigest() == asset['sha256']
        assert not target.exists()
        os.rename(stage,target)
        print(asset['path'],size,flush=True)
    finally:
        if stage.exists():
            stage.unlink()
receipt = root/'provenance.json'
if receipt.exists():
    assert json.loads(receipt.read_text()) == manifest
else:
    receipt.write_text(json.dumps(manifest,indent=2)+'\n')
