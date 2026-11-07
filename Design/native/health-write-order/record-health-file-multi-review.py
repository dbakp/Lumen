"""Persist root review only after explicit individual inspection of every original."""
import argparse,hashlib,json,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--prefix',required=True);p.add_argument('--reviewed-count',type=int,required=True);p.add_argument('--native-json-count',type=int,default=1);a=p.parse_args();b=Path(__file__).resolve().parent
images=json.loads((b/(a.prefix+'-images.json')).read_text());readbacks=json.loads((b/(a.prefix+'-readbacks.json')).read_text());assert len(images)==a.reviewed_count and len(readbacks)==a.native_json_count
for group in [images,readbacks]:
 m=json.loads((Path(group[0]['raw']).parent/'manifest.json').read_text());lookup={v['exportedFileName']:(g['testIdentifier'],v) for g in m for v in g['attachments']}
 for x in group:
  data=(b/x['file']).read_bytes();assert data==Path(x['raw']).read_bytes() and len(data)==x['bytes'] and hashlib.sha256(data).hexdigest()==x['sha256'];assert lookup[x['metadata']['exportedFileName']]==(x['test'],x['metadata'])
for x in images:
 name=x['metadata']['suggestedHumanReadableName'];note='Individually inspected native original viewport; no whole form or all-field visibility claim.'
 if 'held-' in name or 'observed-' in name:note='Preservation/Apple Health consequence and recovering progress visible; Cancel lies below this viewport and is not claimed visible.'
 if 'confirmation' in name:note='Native confirmation title/message/actions complete; gray message is dimmer, no contrast acceptance claimed.'
 if 'shared-photo' in name:note='Synthetic shared photo reference and decoded two-color portrait displayed.'
 if 'record-goals' in name:note='321-step target and absent weight/height/age shown; target fields readable in this viewport.'
 x.update(rootIndividuallyOpened=True,rootProvenanceChecked=True,rootObservation=note)
result=dict(status='Root all retained original screens inspected and full native JSON read; scoped visual review only',source=images[0]['source'],checkedAt=time.time(),providedOriginals=len(images),openedOriginals=len(images),images=images,nativeJSONRead=len(readbacks),nativeJSONProvenance=readbacks[0] if len(readbacks)==1 else readbacks,scope='Main/standard only. Cropped adjacent rows and dim native alert retained; no full appearance/design/VoiceOver acceptance.')
(b/(a.prefix+'-visual-review.json')).write_text(json.dumps(result,indent=2)+'\n');print('Recorded root',len(images),'originals and',len(readbacks),'nativeJSON with exact provenance')
