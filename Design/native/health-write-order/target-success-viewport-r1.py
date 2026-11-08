"""Pure strict replay of the native completion's measured unobscured viewport."""
import math

def rect(value):
    assert type(value) is list and len(value)==4
    assert all(type(n) in [int,float] and math.isfinite(n) for n in value)
    x,y,w,h=value
    assert w>0 and h>0 and math.isfinite(x+w) and math.isfinite(y+h)
    return value

def contains(outer,inner):
    x,y,w,h=outer;a,b,c,d=inner
    return x<=a and y<=b and a+c<=x+w and b+d<=y+h

def validate(row):
    assert row['phase']=='fresh-committed' and row['message']=='Selected data recovered'
    assert row['exists'] is True and row['hittable'] is True and row['wholeSuccessBeforeAnyTestScroll'] is True
    value=row['geometry'];assert type(value) is dict and set(value)=={'application','navigation','label','viewport'}
    app,nav,label,viewport=[rect(value[k]) for k in ['application','navigation','label','viewport']]
    assert contains(app,nav)
    expected=[app[0],nav[1]+nav[3],app[2],app[1]+app[3]-40-(nav[1]+nav[3])]
    rect(expected);assert viewport==expected and contains(viewport,label)
    return {'application':app,'navigation':nav,'label':label,'viewport':viewport}
