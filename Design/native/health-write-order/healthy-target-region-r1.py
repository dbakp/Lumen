"""Pure measured whole-meal region validator for the planned successor."""
import math

def rectangle(value):
    assert isinstance(value,list) and len(value)==4
    assert all(type(x) in [int,float] and math.isfinite(x) for x in value)
    x,y,w,h=value;assert w>0 and h>0
    return x,y,x+w,y+h

def contains(outer,inner):
    return outer[0]<=inner[0] and outer[1]<=inner[1] and inner[2]<=outer[2] and inner[3]<=outer[3]

def validate(row):
    assert row['phase']=='fresh-healthy-target' and row['wholeMealRegionBeforeWorkoutSelection'] is True
    assert row['regionImageSuffix']=='fresh-healthy-region'
    app=rectangle(row['appRect']);nav=rectangle(row['navigationRect']);view=rectangle(row['viewportRect'])
    assert contains(app,nav)
    assert row['viewportRect']==[app[0],nav[3],app[2]-app[0],app[3]-40-nav[3]]
    review=rectangle(row['reviewAnchorRect']);omission=rectangle(row['omissionRect']);region=rectangle(row['regionRect'])
    assert contains(view,review) and contains(view,omission) and contains(view,region) and review[3]<=omission[1]
    assert region==(min(review[0],omission[0]),min(review[1],omission[1]),max(review[2],omission[2]),max(review[3],omission[3]))
    assert row['reviewAnchorExists'] is True and row['reviewAnchorHittable'] is True
    assert row['omissionExists'] is True and row['omissionHittable'] is True
    assert row['omissionEnabled'] is False and row['omissionValue']=='0'
    assert row['workoutEnabledAfterCapture'] is True
    assert type(row['mealToggleExists']) is bool and row['mealToggleEnabled'] is False
    assert type(row['disclosureCount']) is int and row['disclosureCount']>=0
    if row['mealToggleExists']:
        control=rectangle(row['mealToggleRect']);assert row['mealToggleHittable'] is True
    else:
        assert row['mealToggleHittable'] is False and row['mealToggleRect']==[] and row['disclosureCount']==1
        assert row['disclosureLabel'] in ["This saved data can't be replaced here.","Current data opens"]
        control=rectangle(row['disclosureRect'])
    assert contains(view,control) and review[3]<=control[1] and control[3]<=omission[1]
    return True


def validate_readiness(row):
    assert row['phase']=='fresh-workout-ready-visible' and row['beforeMealRegion'] is True
    for key in ['exists','hittable','enabled']:assert row[key] is True
    assert row['value']=='0'
    app=rectangle(row['appRect']);nav=rectangle(row['navigationRect']);view=rectangle(row['viewportRect'])
    assert contains(app,nav)
    assert row['viewportRect']==[app[0],nav[3],app[2]-app[0],app[3]-40-nav[3]]
    assert contains(view,rectangle(row['workoutRect']))
    return True
