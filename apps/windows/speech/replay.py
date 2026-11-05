"""Replay an authorized WAV over the exact packaged worker protocol, without a network ASR service."""
import base64
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
import soundfile
from scipy.signal import resample_poly
from math import gcd
import numpy as np

runtime, worker, models, recording = sys.argv[1:]
samples,rate=soundfile.read(recording,dtype='float32',always_2d=True)
samples=samples.mean(axis=1)
if rate!=16000:
    factor=gcd(rate,16000)
    samples=resample_poly(samples,16000//factor,rate//factor)
with tempfile.TemporaryDirectory() as data:
    requests=[{"cmd":"audio","pcm":base64.b64encode(samples[i:i+4000].astype('<f4')).decode()} for i in range(0,len(samples),4000)]
    requests.append({"cmd":"finish"})
    run=subprocess.run([runtime,worker,"listen",models,str(Path(data)/'profiles.json'),"fixture","0"],
        input=''.join(json.dumps(r)+'\n' for r in requests),capture_output=True,text=True,timeout=180,env=os.environ.copy())
    events=[json.loads(line) for line in run.stdout.splitlines()]
    if run.returncode: raise RuntimeError([e for e in events if e["type"]=="error"] or run.stderr[-1000:])
    finals=[e for e in events if e['type']=='final']
    for event in events:
        if event['type']=='attribution':
            row=next((f for f in finals if f['start']==event['start']),None)
            if row:
                for key in ['speaker','speakerID','voices','overlap']: row[key]=event[key]
    roster=next(e['speakers'] for e in reversed(events) if e['type']=='roster')
    partials=sum(e['type']=='partial' for e in events)
    identities={e['speakerID'] for e in finals if e['speakerID']!='unknown'}
    assert len(roster)>=2 and any(len(row["voices"])>1 for row in finals)
    assert partials and finals and events[-1]['type']=='finished'
    assert sum(e['type']=='ack' for e in events)==len(requests)-1
    bank=json.loads((Path(data)/'profiles.json').read_text())['sessions']['fixture']
    assert 2 <= len(bank['clusters']) <= 8, len(bank['clusters'])
    first=next(iter(identities))
    labeled=subprocess.run([runtime,worker,"name",models,str(Path(data)/'profiles.json'),"fixture",first,"Test speaker"],
        capture_output=True,text=True,timeout=30,check=True)
    result=json.loads(labeled.stdout)
    assert result['type']=='identity' and any(p['name']=='Test speaker' for p in result['profiles'])
    print(json.dumps({"seconds":round(len(samples)/16000,1),"partialUpdates":partials,"finalParagraphs":len(finals),
          "canonicalCandidates":len(bank['clusters']), "rosterSize":len(roster),"dominantIdentities":len(identities),"paragraphParticipants":len({v["id"] for e in finals for v in e["voices"]}),"overlapParagraphs":sum(e['overlap'] for e in finals)}))

    # Simulate a malformed local profile without replacing it. ASR should keep producing text.
    corrupt=Path(data)/'damaged-profiles.json'
    corrupt.write_text('{broken')
    excerpt=requests[:48]+[{"cmd":"finish"}]
    fallback=subprocess.run([runtime,worker,"listen",models,str(corrupt),"degraded","0"],
        input=''.join(json.dumps(r)+'\n' for r in excerpt),capture_output=True,text=True,timeout=90,check=True)
    fallback_events=[json.loads(line) for line in fallback.stdout.splitlines()]
    assert any(e['type']=='warning' for e in fallback_events)
    assert any(e['type']=='final' and e['text'] for e in fallback_events)
    assert fallback_events[-1]['type']=='finished' and corrupt.read_text()=='{broken'
    print('PASS: damaged speaker profile preserved, local ASR continued.')
