"""Isolated planned-successor geometry and actual checker-label expression controls."""
from pathlib import Path
import ast,base64,copy,gzip,hashlib,importlib.util,json,time
B=Path('Design/native/health-write-order')
def module(name):
 spec=importlib.util.spec_from_file_location(name,B/(name+'.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
region=module('healthy-target-region-r1');e=module('healthy-target-evidence-r2');cases=[]
def case(name,accepted,body):
 try:body();actual=True
 except (AssertionError,KeyError,ValueError,TypeError):actual=False
 assert actual is accepted,(name,accepted,actual)
 cases.append({'case':name,'accepted':actual})
row={'phase':'fresh-healthy-target','wholeMealRegionBeforeWorkoutSelection':True,'regionImageSuffix':'fresh-healthy-region','appRect':[0,0,402,874],'navigationRect':[0,78,402,54],'viewportRect':[0,132,402,702],'reviewAnchorRect':[16,300,370,44],'omissionRect':[16,460,370,44],'regionRect':[16,300,370,204],'reviewAnchorExists':True,'reviewAnchorHittable':True,'omissionExists':True,'omissionHittable':True,'omissionEnabled':False,'omissionValue':'0','workoutEnabledAfterCapture':True,'mealToggleExists':True,'mealToggleEnabled':False,'mealToggleHittable':True,'mealToggleRect':[16,370,370,44],'disclosureCount':0,'disclosureLabel':'','disclosureRect':[]}
case('actual-visible-disabled-meal-control',True,lambda:region.validate(row))
disclosed=copy.deepcopy(row);disclosed.update(mealToggleExists=False,mealToggleHittable=False,mealToggleRect=[],disclosureCount=1,disclosureLabel="This saved data can't be replaced here.",disclosureRect=[16,370,370,44])
case('actual-visible-explicit-ineligible-disclosure',True,lambda:region.validate(disclosed))
opened=copy.deepcopy(disclosed);opened['disclosureLabel']='Current data opens';case('actual-visible-current-data-disclosure',True,lambda:region.validate(opened))
for name,field,value in [('offscreen-review','reviewAnchorRect',[16,90,370,44]),('offscreen-omission','omissionRect',[16,820,370,44]),('wrong-union','regionRect',[16,300,370,100]),('invented-gap','viewportRect',[0,144,402,690]),('nonfinite','appRect',[0,0,float('nan'),874]),('bool-coordinate','appRect',[False,0,402,874]),('zero-width','mealToggleRect',[16,370,0,44]),('meal-eligible','mealToggleEnabled',True),('omission-eligible','omissionEnabled',True),('omission-selected','omissionValue','1'),('pending-workout','workoutEnabledAfterCapture',False),('missing-review','reviewAnchorExists',False),('nonhittable-review','reviewAnchorHittable',False),('nonhittable-meal','mealToggleHittable',False),('outside-meal-region','mealToggleRect',[16,550,370,44]),('region-not-before-selection','wholeMealRegionBeforeWorkoutSelection',False),('wrong-image-suffix','regionImageSuffix','fresh-off')]:
 def check(field=field,value=value):
  x=copy.deepcopy(row);x[field]=value;region.validate(x)
 case('geometry-reject-'+name,False,check)
for name,field,value in [('absence-only','disclosureCount',0),('ambiguous-disclosure','disclosureCount',2),('wrong-disclosure','disclosureLabel','Saved data unavailable'),('other-domain-disclosure','disclosureRect',[16,200,370,44]),('absent-meal-hittable','mealToggleHittable',True),('invented-absent-frame','mealToggleRect',[16,370,370,44])]:
 def check(field=field,value=value):
  x=copy.deepcopy(disclosed);x[field]=value;region.validate(x)
 case('disclosure-reject-'+name,False,check)
ready={'phase':'fresh-workout-ready-visible','beforeMealRegion':True,'exists':True,'hittable':True,'enabled':True,'value':'0','appRect':[0,0,402,874],'navigationRect':[0,78,402,54],'viewportRect':[0,132,402,702],'workoutRect':[16,400,370,44]}
case('visible-off-workout-readiness',True,lambda:region.validate_readiness(ready))
for name,field,value in [('missing','exists',False),('offscreen','workoutRect',[16,850,370,44]),('nonhittable','hittable',False),('pending','enabled',False),('already-selected','value','1'),('after-meal','beforeMealRegion',False),('nonfinite','workoutRect',[16,float('inf'),370,44])]:
 def check(field=field,value=value):
  x=copy.deepcopy(ready);x[field]=value;region.validate_readiness(x)
 case('readiness-reject-'+name,False,check)
# Execute the actual matcher and scope assertion extracted from both checker ASTs.
# Input labels derive from the retained240 original index, transformed synthetically;
# the added whole-region label is explicitly synthetic, not a native attachment.
index=json.loads((B/'health-legacy-target-change-string-source240r1-images.json').read_bytes())
labels=[r['metadata']['suggestedHumanReadableName'].replace('health-legacy-target-change-','health-healthy-target-change-') for r in index]
labels.append('health-healthy-target-change-fresh-healthy-region_SYNTHETIC.png')
assert len(labels)==17

def extracted(file):
 tree=ast.parse((B/file).read_text())
 matcher=next(n.value for n in ast.walk(tree) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='matches' for t in n.targets))
 scope=next(n for n in ast.walk(tree) if isinstance(n,ast.Assert) and isinstance(n.test,ast.Compare) and isinstance(n.test.left,ast.Subscript) and isinstance(n.test.left.value,ast.Name) and n.test.left.value.id=='helper' and isinstance(n.test.left.slice,ast.Constant) and n.test.left.slice.value=='scope')
 return compile(ast.Expression(matcher),file,'eval'),compile(ast.Module(body=[scope],type_ignores=[]),file,'exec')
match,scope=extracted('check-healthy-target-r2.py');oldmatch,oldscope=extracted('check-healthy-target-r1.py')
helper={'scope':'actual-healthy-current-file-after-ready-before-confirmation'}
def check_labels(values,matcher=match):
 names=[]
 for label in values:
  matches=eval(matcher,{'e':e,'label':label});assert len(matches)==1;names+=matches
 assert len(names)==17 and len(set(names))==17 and set(names)==set(e.IMAGES)
case('actual-successor-matcher-complete17',True,lambda:check_labels(labels))
case('original241-matcher-still-rejects',False,lambda:check_labels(labels,oldmatch))
case('actual-successor-scope-matches',True,lambda:exec(scope,{'helper':helper}))
case('original241-scope-still-rejects',False,lambda:exec(oldscope,{'helper':helper}))
case('missing-region-image',False,lambda:check_labels(labels[:-1]))
case('duplicate-image',False,lambda:check_labels(labels[:-1]+[labels[0]]))
case('wrong-image-prefix',False,lambda:check_labels([labels[0].replace('healthy-target','legacy-target')]+labels[1:]))
case('wrong-helper-scope',False,lambda:exec(scope,{'helper':{'scope':'actual-legacy-target-change-after-ready-before-confirmation'}}))
raw=json.dumps({'visibleDisabledMeal':row,'visibleDisclosure':disclosed,'transformedRetainedLabels':labels,'syntheticAddedLabel':labels[-1],'caseResults':cases}).encode();fixture='source242-healthy-region-controls-r2-fixtures.json.gz';assert not (B/fixture).exists();(B/fixture).write_bytes(gzip.compress(raw,mtime=0))
report={'status':'PASS isolated wholemeal geometry and actualcheckerlabel/scope controls','cases':len(cases),'accepted':sum(x['accepted'] for x in cases),'rejected':sum(not x['accepted'] for x in cases),'fixture':fixture,'decodedBytes':len(raw),'decodedSHA256':hashlib.sha256(raw).hexdigest(),'scope':'Pure measured geometry plus actualAST matcher/scope expressions with synthetic transformed retained240labels; no242native or new originalscreen claim','checkedAt':time.time()};(B/'source242-healthy-region-controls-r2.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
