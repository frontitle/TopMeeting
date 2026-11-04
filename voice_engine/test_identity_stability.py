"""Logic regressions for runaway online identity creation; no model or private audio."""
import copy
import numpy as np
from engine import Engine,unit


def cluster(identity,vector,number,regions=None):
    return {'id':identity,'number':number,'samples':[{'id':identity,'embedding':vector.tolist(),'seconds':6,'regions':regions or [[0,6]]}],'coverage':regions or [[0,6]]}


def engine(clusters=None):
    e=Engine.__new__(Engine);e.profiles=[];e.profile_aliases={};e.sessions={};e.meeting_id='logic'
    e.bank={'clusters':clusters or [],'aliases':{},'history':[]};e.sessions['logic']=e.bank;e.unknown=e.bank['clusters'];e.recent_regions={};e.pending_candidates=[]
    return e

# Two near-identical anonymous candidates used to create another ID on every call.
a=unit([1,0,0]);b=unit([.99,.08,0]);query=unit([1,.03,0])
e=engine([cluster('guest-a',a,1),cluster('guest-b',b,2)])
for _ in range(1500):
    ident,_,_=e.match(query,seconds=3)
    assert ident=='unknown'
assert len(e.unknown)==2

# Repeated absolute audio time supplies continuity, even when the ranking is tied.
e.recent_regions={'guest-a':[[0,6]],'guest-b':[[10,16]]}
assert e.match(query,3,[[1,4]])[0]=='guest-a'
assert len(e.unknown)==2

# Repeating the same short buffer is not independent evidence of a new speaker.
e=engine()
for _ in range(20):assert e.match(a,1.4,[[0,1.4]])[0]=='unknown'
assert len(e.unknown)==0
assert e.match(a,1.4,[[1.4,2.8]])[0]!='unknown'
assert len(e.unknown)==1

# Truly different clean voices can still increase the count; there is no cap of 3.
e=engine()
for i in range(5):
    v=np.eye(5,dtype=np.float32)[i]
    assert e.match(v,3,[[i*10,i*10+3]])[0]!='unknown'
assert len(e.unknown)==5

# High-confidence anonymous duplicate consolidation is reversible by human naming,
# and never merges two human-confirmed identities or simultaneous-speaker evidence.
left=cluster('guest-a',a,1,[[0,6]])
right=cluster('guest-b',b,2,[[10,16]])
for c in [left,right]:c['samples']=[dict(c['samples'][0],id=c['id']+str(i)) for i in range(3)]
e=engine(copy.deepcopy([left,right]));e.coalesce_anonymous();assert e.canonical('guest-b')=='guest-a'
e=engine(copy.deepcopy([left,right]));e.bank['cannotLinks']=[['guest-a','guest-b']];e.coalesce_anonymous();assert e.canonical('guest-b')=='guest-b'
e=engine(copy.deepcopy([left,right]));e.unknown[1]['confirmed']=True;e.coalesce_anonymous();assert e.canonical('guest-b')=='guest-b'
print('PASS: 1500 ambiguous observations create no new IDs; sliding-window continuity; unique-audio candidate support; no fixed participant cap; guarded anonymous consolidation')
