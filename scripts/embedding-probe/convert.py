"""Offline MedEmbed export with independent padding-mask checks.

Usage: python convert.py SOURCE FIXTURE UPSTREAM_REPORT OUTPUT_PACKAGE REPORT
The 256-token/native interface is deliberately fixed to the evaluated contract.
This creates an evaluation artifact; it neither installs nor enables an app model.
"""
import os
os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
os.environ['TOKENIZERS_PARALLELISM'] = 'false'
import hashlib
import json
import platform
import sys
import time
from pathlib import Path
import numpy as np
import torch
import coremltools as ct
import transformers
from pin import verify_source
from transformers import BertModel

source, fixture, reference_path, destination, report_path = map(Path, sys.argv[1:])
assert destination.suffix == '.mlpackage' and not destination.exists()
provenance = verify_source(source)
pool = json.loads((source/'1_Pooling/config.json').read_text())
assert pool['pooling_mode_cls_token'] and not pool['pooling_mode_mean_tokens']
reference = json.loads(reference_path.read_text())
assert reference['fixtureSHA256'] == hashlib.sha256(fixture.read_bytes()).hexdigest()
assert reference['sourceRevision'] == provenance['revision'] and reference['windowProofVersion'] == 1

class FiniteMaskBert(BertModel):
    def get_extended_attention_mask(self, attention_mask, input_shape, device=None, dtype=None):
        assert not self.config.is_decoder and attention_mask.ndim == 2
        # The default FP32 minimum becomes -infinity during FP16 conversion;
        # multiplying that by an unmasked zero produced NaNs in the first export.
        # A finite additive padding mask keeps the evaluated valid-token result.
        extended = attention_mask[:, None, None, :].to(dtype=dtype or self.dtype)
        return (1.0-extended)*-10000.0

class Encoder(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model
    def forward(self, input_ids, attention_mask, token_type_ids):
        hidden = self.model(input_ids=input_ids, attention_mask=attention_mask, token_type_ids=token_type_ids, return_dict=False)[0]
        return torch.nn.functional.normalize(hidden[:, 0, :], p=2, dim=1)

model = FiniteMaskBert.from_pretrained(source, local_files_only=True, trust_remote_code=False, attn_implementation='eager', use_safetensors=True).eval()
torch.set_num_threads(4)
encoder = Encoder(model).eval()
maximum, count, example = 0.0, 0, None
with torch.no_grad():
    for row in reference['cases']:
        if row['passageStatus'] != 'used':
            continue
        for ids, mask, expected in zip(row['windowTokenIDs'], row['windowMasks'], row['passageVectors'], strict=True):
            assert len(ids) == len(mask) == 256
            inputs = (torch.tensor([ids], dtype=torch.int32), torch.tensor([mask], dtype=torch.int32), torch.zeros((1,256), dtype=torch.int32))
            actual = encoder(*inputs)[0].tolist()
            maximum = max(maximum, max(abs(a-b) for a,b in zip(actual,expected,strict=True)))
            count += 1
            if example is None:
                example = inputs
    assert count > 0 and maximum < 1e-6, maximum
    traced = torch.jit.trace(encoder, example, strict=True)
start = time.monotonic()
converted = ct.convert(traced, convert_to='mlprogram', inputs=[ct.TensorType(name=name,shape=(1,256),dtype=np.int32) for name in ['input_ids','attention_mask','token_type_ids']], outputs=[ct.TensorType(name='div_1',dtype=np.float32)], minimum_deployment_target=ct.target.iOS18, compute_precision=ct.precision.FLOAT16, skip_model_load=True)
converted.author = 'Lumen conversion of Abhinand Balachandran / MedEmbed'
converted.license = 'Apache-2.0 (MedEmbed); MIT (BGE base)'
converted.short_description = 'Evaluation only: English medical-topic embeddings, CLS pooling and L2 normalization. Not clinical interpretation.'
for key,value in {'source_repository':provenance['repository'],'source_revision':provenance['revision'],'pooling':'CLS then L2 normalization','sequence_length':'256; reject overlong queries or window complete passages','mask_representation':'finite -10000 on padded positions, zero on valid tokens'}.items():
    converted.user_defined_metadata[key] = value
converted.save(destination)
files = [{'path':str(p.relative_to(destination)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(destination.rglob('*')) if p.is_file()]
report = {'scope':'Portable evaluation export; exact candidate native parity/retrieval/device gates remain separate. Package identifiers may differ on re-export; only the measured artifact hashes bind a selected package.','sourceRepository':provenance['repository'],'sourceRevision':provenance['revision'],'python':platform.python_version(),'torch':torch.__version__,'transformers':transformers.__version__,'coremltools':ct.__version__,'numpy':np.__version__,'conversionSeconds':time.monotonic()-start,'sequenceLength':256,'pooling':'CLS then L2 normalization','precision':'FLOAT16','maskRepresentation':'finite -10000 for padded positions, zero for real tokens','maskReferenceWindowCount':count,'maskFP32MaximumElementDifference':maximum,'referenceSHA256':hashlib.sha256(reference_path.read_bytes()).hexdigest(),'fixtureSHA256':reference['fixtureSHA256'],'minimumDeploymentTarget':'iOS18','files':files}
report_path.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({key:report[key] for key in ['maskReferenceWindowCount','maskFP32MaximumElementDifference','conversionSeconds','files']}))
