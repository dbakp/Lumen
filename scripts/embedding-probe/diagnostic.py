"""Recreate the saved input-configuration diagnostic from native probe vectors.

Usage: python diagnostic.py PARITY_FIXTURE NATIVE_VECTORS CORPUS CONFIG MODEL_ID OUTPUT
CONFIG contributes only input/label fields; its recorded scores are never used.
"""
import hashlib
import json
import math
import sys
from pathlib import Path
fixture_path, native_path, corpus_path, config_path = map(Path, sys.argv[1:5])
model_id, output_path = sys.argv[5], Path(sys.argv[6])
fixture, native, corpus, configuration = [json.loads(p.read_text()) for p in (fixture_path,native_path,corpus_path,config_path)]
assert hashlib.sha256(fixture_path.read_bytes()).hexdigest() == native['fixtureSHA256']
texts = {x['id']:x['text'] for x in fixture['cases']}
vectors = {texts[x['id']]:x['queryVector'] for x in native['cases'] if x['queryStatus']=='used'}
def similarity(x,y):
    assert len(x)==len(y)==384 and all(math.isfinite(v) for v in x+y)
    return sum(a*b for a,b in zip(x,y))/math.sqrt(sum(v*v for v in x)*sum(v*v for v in y))
rows=[]
for sample in configuration['cases']:
    query=vectors[sample['question']]
    scores=[]
    for document in corpus['documents']:
        text=document['title']+'\n'+document['body'] if sample['documentInput']=='title+body' else document['body']
        scores.append({'documentID':document['id'],'similarity':similarity(query,vectors[text])})
    rows.append({key:sample[key] for key in ['id','form','question','documentInput','expected']} | {'scores':sorted(scores,key=lambda x:-x['similarity'])})
report={'scope':'Reproducible synthetic input-configuration diagnostic from native vectors. Manual compact forms remain hypotheses, not a shipped transformation, model/cutoff decision or independent clinical benchmark.','modelID':model_id,'nativeVectorReportSHA256':hashlib.sha256(native_path.read_bytes()).hexdigest(),'fixtureSHA256':native['fixtureSHA256'],'cases':rows}
output_path.write_text(json.dumps(report,indent=2)+'\n')
print('Recreated',len(rows),'configurations from native encoder outputs.')
