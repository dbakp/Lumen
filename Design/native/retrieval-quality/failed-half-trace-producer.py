import os,json,time,platform,hashlib
from pathlib import Path
os.environ['HF_HUB_OFFLINE']='1';os.environ['TRANSFORMERS_OFFLINE']='1';os.environ['TOKENIZERS_PARALLELISM']='false'
import torch,numpy as np,coremltools as ct,transformers
from transformers import AutoModel,AutoTokenizer
source=Path('/tmp/LumenBatch26MedEmbedSource');destination=Path('/tmp/LumenBatch26Probe/medembed-small-v0.1-fp16-half-trace.mlpackage')
config=json.loads((source/'1_Pooling/config.json').read_text());assert config['pooling_mode_cls_token'] and not config['pooling_mode_mean_tokens']
model=AutoModel.from_pretrained(source,local_files_only=True,trust_remote_code=False,attn_implementation='eager').eval().half();torch.set_num_threads(4)
class Encoder(torch.nn.Module):
 def __init__(self,model):super().__init__();self.model=model
 def forward(self,input_ids,attention_mask,token_type_ids):
  hidden=self.model(input_ids=input_ids,attention_mask=attention_mask,token_type_ids=token_type_ids,return_dict=False)[0]
  return torch.nn.functional.normalize(hidden[:,0,:],p=2,dim=1)
encoder=Encoder(model).eval();tokenizer=AutoTokenizer.from_pretrained(source,local_files_only=True,trust_remote_code=False)
example=tokenizer('Synthetic export verification sentence.',return_tensors='pt',padding='max_length',max_length=256,truncation=False)
inputs=tuple(example[name].to(dtype=torch.int32) for name in ['input_ids','attention_mask','token_type_ids'])
with torch.no_grad():traced=torch.jit.trace(encoder,inputs,strict=True)
start=time.monotonic()
converted=ct.convert(traced,convert_to='mlprogram',inputs=[ct.TensorType(name=name,shape=(1,256),dtype=np.int32) for name in ['input_ids','attention_mask','token_type_ids']],outputs=[ct.TensorType(name='div_1',dtype=np.float32)],minimum_deployment_target=ct.target.iOS18,compute_precision=ct.precision.FLOAT16,skip_model_load=True)
converted.author='Lumen conversion of Abhinand Balachandran / MedEmbed';converted.license='Apache-2.0 (MedEmbed); MIT (BGE base)';converted.short_description='English medical-topic embeddings, CLS pooling and L2 normalization. Retrieval only; not clinical interpretation.'
converted.user_defined_metadata['source_repository']='abhinand/MedEmbed-small-v0.1';converted.user_defined_metadata['source_revision']='40a5850d046cfdb56154e332b4d7099b63e8d50e';converted.user_defined_metadata['pooling']='CLS then L2-normalization';converted.user_defined_metadata['sequence_length']='256; callers must reject overlong questions or window complete passages'
converted.save(destination)
files=[{'path':str(p.relative_to(destination)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(destination.rglob('*')) if p.is_file()]
report={'scope':'Reproducible conversion only; Core ML parity/retrieval/device behavior not yet proven.','sourceRepository':'abhinand/MedEmbed-small-v0.1','sourceRevision':'40a5850d046cfdb56154e332b4d7099b63e8d50e','python':platform.python_version(),'torch':torch.__version__,'transformers':transformers.__version__,'coremltools':ct.__version__,'numpy':np.__version__,'conversionSeconds':time.monotonic()-start,'sequenceLength':256,'output':'div_1','pooling':'CLS, L2 normalized','precision':'FLOAT16','traceSourceDtype':'FLOAT16 (original FP32 reference retained separately)','minimumDeploymentTarget':'iOS18','files':files}
Path('/tmp/LumenBatch26Probe/conversion-half-trace.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report),flush=True)
