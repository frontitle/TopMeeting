"""Real-speech regression. Public human recordings + existing app microphone files.
No synthetic speech. The overlap control is an explicitly mixed human-recording fixture.
"""
import copy
import uuid
import json
import sys
import tempfile
import time
from pathlib import Path
import numpy as np
import soundfile as sf
from engine import Engine, audio, RATE

ROOT = Path(__file__).resolve().parent.parent
report = {'date':'2026-11-03','fixture':'k2-fsa/sherpa-onnx speaker-segmentation-models/0-four-speakers-zh.wav','checks':[]}
with tempfile.TemporaryDirectory() as tmp:
    e = Engine(ROOT/'voice_engine/models',Path(tmp)/'profiles.json')
    raw = audio(ROOT/'tests_audio/four-speakers-zh.wav')
    for name,start,end in [('enroll-a',1,5),('enroll-b',28,32),('heldout-a',22,25),('heldout-b',34,37)]:
        sf.write(ROOT/f'tests_audio/{name}.wav',raw[start*RATE:end*RATE],RATE)
    e.reset('automatic-meeting')
    initial = np.concatenate([raw[1*RATE:5*RATE],raw[28*RATE:32*RATE]])
    discovered = e.infer(initial)
    source_a = next(event['speakerIDs'][0] for event in discovered['events'] if event['start']<2 and not event['overlap'])
    source_b = next(event['speakerIDs'][0] for event in discovered['events'] if event['start']>4.5 and not event['overlap'])
    assert source_a != source_b
    assert not e.profiles, 'Anonymous discovery silently enrolled a person'
    named_a = e.name_or_merge('automatic-meeting',source_a,'测试声纹 A')
    named_b = e.name_or_merge('automatic-meeting',source_b,'测试声纹 B')
    profile_a = named_a['mappings'][source_a]
    report['checks'].append({'test':'automatic discovery then quick naming, no pre-enrollment','anonymousSpeakers':len(e.unknown),'profilesAfterNaming':len(e.profiles)})
    for name,start,end in [('测试声纹 A',22,25),('测试声纹 B',34,38)]:
        ident,label,similarity = e.match(e.embedding(raw[start*RATE:end*RATE]))
        assert label == name, (name,label,similarity)
        report['checks'].append({'test':'held-out speaker matching','expected':name,'matched':label,'cosine':round(similarity,4),'enrollmentAndTestDisjoint':True})
    _,label,_ = e.match(e.embedding(raw[11*RATE:16*RATE]))
    assert label not in ['测试声纹 A','测试声纹 B']
    report['checks'].append({'test':'unenrolled speaker rejection','matched':label})
    alternating = np.concatenate([raw[22*RATE:25*RATE],raw[34*RATE:37*RATE]])
    result = e.infer(alternating)
    names = {name for event in result['events'] for name in event['speakers']}
    assert {'测试声纹 A','测试声纹 B'} <= names, result
    report['checks'].append({'test':'speaker switch without silence','events':result['events'],'inferenceSeconds':result['inferenceSeconds']})
    mixture = raw[22*RATE:25*RATE]*.5+raw[34*RATE:37*RATE]*.5
    result = e.infer(mixture)
    detected = sum(t['end']-t['start'] for t in result['events'] if t['overlap'])
    assert detected > .5, result
    report['checks'].append({'test':'controlled overlap of two real human recordings','duration':3,'detectedOverlapSeconds':round(detected,3),'events':result['events'],'limitation':'Controlled digital mixture, not a live argument. Missed overlap remains; not a validated recall estimate.'})
    # Reproduce a mistaken split using a second cluster backed by a disjoint real
    # utterance of speaker A. This is an induced split regression, not an accuracy metric.
    original = next(c for c in e.unknown if c['id']==source_a)
    duplicate = {'id':'guest-'+str(uuid.uuid4()),'number':len(e.unknown)+1,'samples':[], 'coverage':[]}
    e.unknown.append(duplicate)
    e.add_observation(duplicate,e.embedding(raw[22*RATE:25*RATE]),3,[[22,25]])
    before = len(next(p for p in e.profiles if p['id']==profile_a)['exemplars'])
    anchor = copy.deepcopy(next(p for p in e.profiles if p['id']==profile_a)['exemplars'][0])
    merged = e.name_or_merge('automatic-meeting',duplicate['id'],target=profile_a)
    after = len(next(p for p in e.profiles if p['id']==profile_a)['exemplars'])
    assert e.canonical(duplicate['id']) == profile_a and after > before
    assert next(p for p in e.profiles if p['id']==profile_a)['exemplars'][0] == anchor
    reloaded = Engine(ROOT/'voice_engine/models',Path(tmp)/'profiles.json')
    assert reloaded.canonical(duplicate['id'],reloaded.sessions['automatic-meeting']) == profile_a
    report['checks'].append({'test':'manual merge feeds multi-exemplar voice model','inducedSplitFromRealSpeech':True,'exemplarsBefore':before,'exemplarsAfter':after,'anchorPreserved':True,'mappingPersisted':True})
    e.undo_identity('automatic-meeting')
    assert e.canonical(duplicate['id']) == duplicate['id']
    assert len(next(p for p in e.profiles if p['id']==profile_a)['exemplars']) == before
    report['checks'].append({'test':'undo merge restores identity and learned samples','passed':True})
    existing_name = next(p for p in e.profiles if p['id']==profile_a)['name']
    created = e.name_or_merge('automatic-meeting',source_a,'新人员',new_person=True)
    assert next(p for p in e.profiles if p['id']==profile_a)['name'] == existing_name
    assert created['localOnly'] is True
    e.undo_identity('automatic-meeting')
    report['checks'].append({'test':'inline new person does not rename an existing global person','passed':True})
    profile_b = next(p for p in e.profiles if p['name']=='测试声纹 B')['id']
    wrong = e.name_or_merge('automatic-meeting',profile_b,target=profile_a)
    assert wrong['quarantined'] > 0, wrong
    assert not any(p['id']==profile_b for p in e.profiles)
    assert e.canonical(profile_b,{'aliases':{}}) == profile_a
    e.undo_identity('automatic-meeting')
    assert any(p['id']==profile_b for p in e.profiles)
    report['checks'].append({'test':'contradictory manual merge quarantines acoustic outliers and is reversible','quarantined':wrong['quarantined']})
    e.reset('silence-meeting'); e.infer(np.zeros(6*RATE,np.float32))
    assert len(e.unknown) == 0
    report['checks'].append({'test':'silence creates no anonymous identity','passed':True})
    e.reset('mixed-meeting'); e.infer(mixture)
    clean_samples = sum(len(c['samples']) for c in e.unknown)
    report['checks'].append({'test':'mixed audio uses only confident single-speaker frames for candidate collection','candidateSamples':clean_samples,'limitation':'Neural overlap misses can still contaminate candidates; human-confirmed merges use additional outlier checks.'})
    # Private recordings stay local; do not expose speech or build named profiles from them.
    report['appRecordings'] = []
    for path in sorted((Path.home()/'Library/Application Support/TopMeeting').glob('*.caf')):
        e.reset('private-diagnostic-'+path.stem); samples = audio(path); timeline = []; times = []
        for end in range(2*RATE,len(samples)+2*RATE,2*RATE):
            end = min(end,len(samples)); start = max(0,end-e.window)
            r = e.infer(samples[start:end],start/RATE); times.append(r['inferenceSeconds'])
            timeline = [t for t in timeline if t['end'] <= r['replaceFrom']]+r['events']
        report['appRecordings'].append({'file':path.name,'durationSeconds':round(len(samples)/RATE,2),'speechIntervals':len(timeline),'overlapSeconds':round(sum(t['end']-t['start'] for t in timeline if t['overlap']),3),'meanInferenceSeconds':round(float(np.mean(times)),4),'limitation':'No manually labelled speaker/overlap ground truth. These numbers are diagnostics, not accuracy.'})
    report['profilesPersistence'] = Engine(ROOT/'voice_engine/models',Path(tmp)/'profiles.json').roster()
    report['profileFilePermissions'] = oct((Path(tmp)/'profiles.json').stat().st_mode & 0o777)
(ROOT/'reports/voice-recording-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False,indent=2))
