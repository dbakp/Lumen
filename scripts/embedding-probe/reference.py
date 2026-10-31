"""Independent, offline upstream FP32 reference for the native parity probe.

Usage: python reference.py SOURCE_DIRECTORY FIXTURE_JSON OUTPUT_JSON
Requires the pinned evaluation environment recorded beside its result.
"""
import os
os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
os.environ['TOKENIZERS_PARALLELISM'] = 'false'
import hashlib
import json
import sys
from pathlib import Path
from pin import verify_source
import torch
from transformers import AutoModel, AutoTokenizer

source, fixture_path, output = map(Path, sys.argv[1:])
provenance = verify_source(source)
pool = json.loads((source / '1_Pooling/config.json').read_text())
assert pool['pooling_mode_cls_token'] and not pool['pooling_mode_mean_tokens']
model = AutoModel.from_pretrained(source, local_files_only=True, trust_remote_code=False, attn_implementation='eager', use_safetensors=True).eval()
tokenizer = AutoTokenizer.from_pretrained(source, local_files_only=True, trust_remote_code=False)
torch.set_num_threads(4)
raw_fixture = fixture_path.read_bytes()
fixture = json.loads(raw_fixture)
assert 0 < len(fixture['cases']) <= 256
rows = []

def vector(ids):
    valid = [101] + ids + [102]
    encoded = {
        'input_ids': torch.tensor([valid + [0] * (256-len(valid))]),
        'attention_mask': torch.tensor([[1] * len(valid) + [0] * (256-len(valid))]),
        'token_type_ids': torch.zeros((1, 256), dtype=torch.int64),
    }
    with torch.no_grad():
        return torch.nn.functional.normalize(model(**encoded).last_hidden_state[:, 0, :], p=2, dim=1)[0].tolist()

for sample in fixture['cases']:
    text = sample['text']
    row = {'id': sample['id']}
    # Controller bounds are explicit. Reference tokenization and vectors come
    # independently from the immutable upstream tokenizer and original model.
    if len(text.encode('utf-8')) > 32000 or len(text) > 8000:
        row.update(tokenStatus='inputLimit', queryStatus='inputLimit', passageStatus='inputLimit')
    else:
        ids = tokenizer.encode(text, add_special_tokens=False, truncation=False)
        row['tokenIDs'] = ids
        windows = []
        window_ids, window_masks = [], []
        start = 0
        while start < len(ids):
            end = min(len(ids), start + 254)
            window_ids.append([101] + ids[start:end] + [102] + [0] * (254-(end-start)))
            window_masks.append([1] * (end-start+2) + [0] * (254-(end-start)))
            windows.append(vector(ids[start:end]))
            if end == len(ids):
                break
            start = end - 32
        row.update(windowTokenIDs=window_ids, windowMasks=window_masks)
        if not ids:
            row.update(queryStatus='empty', passageStatus='empty')
        else:
            row.update(passageStatus='used', passageVectors=windows)
            if len(windows) > 1:
                row['queryStatus'] = 'queryTooLong'
            else:
                row.update(queryStatus='used', queryVector=windows[0])
    rows.append(row)
output.write_text(json.dumps({'scope': 'Unmodified pinned upstream FP32 BERT with declared CLS/L2 modules, offline tokenizer; not clinical/device validation', 'windowProofVersion': 1, 'fixtureSHA256': hashlib.sha256(raw_fixture).hexdigest(), 'sourceRevision': provenance['revision'], 'cases': rows}, indent=2) + '\n')
print('Recorded', len(rows), 'independent upstream reference cases.')
