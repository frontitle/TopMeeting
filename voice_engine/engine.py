"""Local neural speaker verification and overlap detection. No network access.
Segmentation powerset mapping follows k2-fsa/sherpa-onnx's MIT example.
"""
import copy
import base64
import hashlib
import json
import math
import os
import sys
import time
import uuid
from pathlib import Path

import numpy as np
import onnxruntime as ort
import sherpa_onnx
import soundfile as sf
from scipy.signal import resample_poly

RATE = 16000
MAPPING = np.array([[0,0,0],[1,0,0],[0,1,0],[0,0,1],[1,1,0],[1,0,1],[0,1,1]], dtype=np.int8)


def unit(value):
    value = np.asarray(value, dtype=np.float32)
    norm = float(np.linalg.norm(value))
    if norm < 1e-8 or not np.isfinite(value).all():
        raise ValueError('声纹样本无效，请等待更清晰的单人发言后标记。')
    return value / norm


def audio(path):
    data, rate = sf.read(path, dtype='float32', always_2d=True)
    data = data.mean(axis=1)
    if rate != RATE:
        divisor = math.gcd(rate, RATE)
        data = resample_poly(data, RATE // divisor, rate // divisor)
    return np.ascontiguousarray(data, dtype=np.float32)


def runs(mask):
    padded = np.pad(mask.astype(np.int8), (1,1))
    edges = np.diff(padded)
    return list(zip(np.where(edges == 1)[0], np.where(edges == -1)[0]))


class Engine:
    def __init__(self, root, profiles):
        root = Path(root)
        options = ort.SessionOptions()
        options.intra_op_num_threads = 2
        options.inter_op_num_threads = 1
        self.seg = ort.InferenceSession(str(root / 'sherpa-onnx-pyannote-segmentation-3-0/model.onnx'), options, providers=['CPUExecutionProvider'])
        meta = self.seg.get_modelmeta().custom_metadata_map
        self.window = int(meta['window_size'])
        self.shift = int(meta['receptive_field_shift'])
        self.field = int(meta['receptive_field_size'])
        model = root / 'embedding.onnx'
        self.model_id = hashlib.sha256(model.read_bytes()).hexdigest()
        config = sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=str(model), num_threads=2, provider='cpu')
        if not config.validate(): raise ValueError('声纹模型配置无效。')
        self.extractor = sherpa_onnx.SpeakerEmbeddingExtractor(config)
        self.path = Path(profiles)
        self.profiles = []
        self.sessions = {}
        self.profile_aliases = {}
        if self.path.exists():
            saved = json.loads(self.path.read_text())
            if saved.get('model') != self.model_id: raise ValueError('声纹模型已变化，请迁移或重新确认声纹。')
            self.profiles = saved['profiles']
            self.sessions = saved.get('sessions',{})
            self.profile_aliases = saved.get('profileAliases',{})
        self.reset()

    def reset(self, meeting_id='temporary', observation_offset=0):
        self.buffer = np.zeros(0, np.float32)
        self.total = 0
        self.last_inference = 0
        self.last_saved = 0
        self.observation_offset = observation_offset
        self.meeting_id = meeting_id
        self.bank = self.sessions.setdefault(meeting_id,{'clusters':[], 'aliases':{}, 'history':[]})
        self.unknown = self.bank['clusters']
        self.recent_regions = {}
        self.pending_candidates = []

    def canonical(self, identity, bank=None):
        bank = bank or self.bank
        seen = set()
        while (identity in bank['aliases'] or identity in self.profile_aliases) and identity not in seen:
            seen.add(identity); identity = bank['aliases'].get(identity,self.profile_aliases.get(identity))
        return identity

    def profile_vectors(self, profile):
        return [unit(v) for v in (profile.get('exemplars') or ([profile['embedding']] if profile.get('embedding') else []))]

    def label(self, identity):
        identity = self.canonical(identity)
        for p in self.profiles:
            if p['id'] == identity: return p['name']
        for c in self.unknown:
            if c['id'] == identity: return f"说话人 {c['number']}"
        return '未知说话人'

    def roster(self):
        return [{k:p[k] for k in ('id','name','seconds')} for p in self.profiles]

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        tmp = self.path.with_suffix('.tmp')
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd,'w') as f: json.dump({'model':self.model_id,'profiles':self.profiles,'sessions':self.sessions,'profileAliases':self.profile_aliases},f)
        os.replace(tmp,self.path)
        os.chmod(self.path,0o600)

    def embedding(self, samples):
        if len(samples) < int(.8 * RATE): return None
        stream = self.extractor.create_stream()
        stream.accept_waveform(sample_rate=RATE, waveform=np.ascontiguousarray(samples,np.float32))
        stream.input_finished()
        if not self.extractor.is_ready(stream): return None
        return unit(self.extractor.compute(stream))

    def segment(self, samples):
        valid = len(samples)
        x = np.pad(samples,(0,max(0,self.window-valid)))[:self.window]
        out = self.seg.run(None,{self.seg.get_inputs()[0].name:x.reshape(1,1,-1).astype(np.float32)})[0][0]
        probabilities = np.exp(out - np.max(out,axis=1,keepdims=True))
        probabilities /= probabilities.sum(axis=1,keepdims=True)
        classes = probabilities.argmax(axis=1)
        labels = MAPPING[classes]
        speech = (1-probabilities[:,0]) > .6
        pair_probability = probabilities[:,4:].sum(axis=1)
        overlap = (pair_probability > .55) & (labels.sum(axis=1) >= 2)
        labels[~speech] = 0
        frames = min(len(labels), max(0,int((valid-self.field/2)/self.shift)))
        labels, overlap = labels[:frames], overlap[:frames]
        # Ignore isolated neural spikes shorter than 200 ms, not all short speech.
        for a,b in runs(overlap):
            if (b-a)*self.shift/RATE < .2: overlap[a:b] = False
        # A confirmed interruption often fades at either edge. Follow the same
        # pair while it remains the most probable class, without triggering
        # a new interruption from weak evidence or changing speaker identities.
        for pair in (4,5,6):
            edges = (classes[:frames] == pair) & (pair_probability[:frames] >= .40)
            for start,end in runs(edges):
                if overlap[start:end].any(): overlap[start:end] = True
        return labels, overlap, probabilities[:frames]

    def isolated(self, samples, labels, track, probabilities=None):
        mask = (labels[:,track] == 1) & (labels.sum(axis=1) == 1)
        if probabilities is not None: mask &= (probabilities[:,4:].sum(axis=1)<.2) & ((1-probabilities[:,0])>.8)
        pieces = []
        for a,b in runs(mask):
            start = max(0,int(a*self.shift+self.field/2))
            end = min(len(samples),int(b*self.shift+self.field/2))
            if end-start >= int(.25*RATE): pieces.append(samples[start:end])
        return np.concatenate(pieces) if pieces else np.zeros(0,np.float32)

    @staticmethod
    def region_overlap(left, right):
        return sum(max(0, min(b,d)-max(a,c)) for a,b in left for c,d in right)

    @staticmethod
    def region_seconds(regions):
        return sum(b-a for a,b in regions)

    def coalesce_anonymous(self):
        # Only combine independently supported anonymous clusters. Human-confirmed
        # identities and named profiles are never silently merged.
        active = [c for c in self.unknown if c['id'].startswith('guest-') and not c.get('confirmed')
                  and self.canonical(c['id']) == c['id'] and len(c['samples']) >= 3
                  and self.region_seconds(c['coverage']) >= 5]
        for i,left in enumerate(active):
            if self.canonical(left['id']) != left['id']: continue
            a = np.array([unit(o['embedding']) for o in left['samples']])
            for right in active[i+1:]:
                if self.canonical(right['id']) != right['id']: continue
                pair = sorted([left['id'],right['id']])
                if any(sorted(set(self.canonical(x) for x in link)) == pair for link in self.bank.get('cannotLinks',[])): continue
                b = np.array([unit(o['embedding']) for o in right['samples']])
                if float(unit(a.mean(axis=0)) @ unit(b.mean(axis=0))) < .88: continue
                cross = a @ b.T
                if min(float(np.quantile(cross.max(axis=1),.25)),float(np.quantile(cross.max(axis=0),.25))) < .80: continue
                self.bank['aliases'][right['id']] = left['id']
                merged = sorted(left['coverage']+right['coverage'])
                coverage = []
                for start,end in merged:
                    if coverage and start <= coverage[-1][1]: coverage[-1][1] = max(coverage[-1][1],end)
                    else: coverage.append([start,end])
                left['coverage'] = coverage
                merged_samples = left['samples'] + right['samples']
                left['samples'] = merged_samples if len(merged_samples)<=20 else [merged_samples[0]]+merged_samples[-19:]
                # Future windows should also recognise the just-resolved track.
                if right['id'] in self.recent_regions: self.recent_regions[left['id']] = self.recent_regions[right['id']]
                a = np.array([unit(o['embedding']) for o in left['samples']])

    def accept_cluster(self, cluster, vector, seconds, regions, score):
        self.last_match_source = cluster['id']
        self.recent_regions[self.canonical(cluster['id'])] = regions or []
        observation = self.add_observation(cluster,vector,seconds,regions)
        identity = self.canonical(cluster['id'])
        profile = next((p for p in self.profiles if p['id']==identity),None)
        if cluster.get('confirmed') and observation and profile and score>=.80:
            self.learn_profile(profile,[observation])
        identity = self.canonical(cluster['id'])
        return (identity,self.label(identity),score)

    def match(self, vector, seconds=0, regions=None):
        self.last_match_source = 'unknown'
        if vector is None or (regions is not None and seconds < 1.2): return ('unknown','未知说话人',0.0)
        grouped = {}
        for c in self.unknown:
            vectors = [unit(v['embedding']) for v in c['samples']]
            if not vectors: continue
            score = max(float(vector@v) for v in vectors)
            identity = self.canonical(c['id'])
            if identity not in grouped or score>grouped[identity][0]: grouped[identity] = (score,c)
        candidates = sorted(grouped.values(),key=lambda item:item[0],reverse=True)
        # The same clean audio reappears in successive 10 s sliding windows.
        # Use its absolute time overlap as continuity evidence, not as new people.
        if regions:
            shared = sorted([(self.region_overlap(regions,self.recent_regions.get(identity,[])),score,c)
                             for identity,(score,c) in grouped.items()],key=lambda x:x[0],reverse=True)
            if shared and shared[0][0]>=.8 and shared[0][1]>=.55 and (len(shared)==1 or shared[0][0]-shared[1][0]>=.4):
                _,score,c = shared[0]
                return self.accept_cluster(c,vector,seconds,regions,score)
        scored = []
        for p in self.profiles:
            vectors = self.profile_vectors(p)
            if vectors:
                centroid = unit(np.mean(vectors,axis=0))
                score = .7*max(float(vector@v) for v in vectors)+.3*float(vector@centroid)
                scored.append((score,p))
        scored.sort(key=lambda x:x[0],reverse=True)
        if scored:
            best,p = scored[0]; margin = best-(scored[1][0] if len(scored)>1 else 0)
            if best >= .62 and margin >= .08:
                local = [c for c in self.unknown if self.canonical(c['id'])==p['id']]
                c = max(local,key=lambda c:max([float(vector@unit(o['embedding'])) for o in c['samples']] or [-1])) if local else None
                if c is None:
                    c = {'id':p['id'],'number':len(self.unknown)+1,'samples':[],'coverage':[]}
                    self.unknown.append(c)
                return self.accept_cluster(c,vector,seconds,regions,best)
        best = candidates[0][0] if candidates else -1
        if candidates and best >= .72:
            if len(candidates)==1 or best-candidates[1][0]>=.08:
                return self.accept_cluster(candidates[0][1],vector,seconds,regions,best)
            # Ambiguous is not novel. Never manufacture another near-duplicate.
            return ('unknown','未知说话人',best)
        if best >= .60 or seconds < 1.2:
            return ('unknown','未知说话人',max(0,best))
        if regions is not None and seconds < 2.4:
            now = max((b for _,b in regions),default=0)
            self.pending_candidates = [p for p in self.pending_candidates if now-max((b for _,b in p['regions']),default=0)<=20]
            pending = next((p for p in self.pending_candidates if float(vector@p['vector'])>=.75),None)
            if pending:
                pending['count'] += 1
                pending['seconds'] += max(0,self.region_seconds(regions)-self.region_overlap(regions,pending['regions']))
                pending['regions'] = regions; pending['vector'] = vector
                if pending['count'] < 2 or pending['seconds'] < 2.4: return ('unknown','未知说话人',0.0)
                self.pending_candidates = [p for p in self.pending_candidates if p is not pending]
            else:
                self.pending_candidates.append({'vector':vector,'count':1,'seconds':self.region_seconds(regions),'regions':regions})
                self.pending_candidates = self.pending_candidates[-10:]
                return ('unknown','未知说话人',0.0)
        number = max([c['number'] for c in self.unknown] or [0])+1
        while any(p['name']==f'说话人 {number}' for p in self.profiles): number += 1
        c = {'id':'guest-'+str(uuid.uuid4()),'number':number,'samples':[], 'coverage':[]}
        self.unknown.append(c)
        return self.accept_cluster(c,vector,seconds,regions,0.0)

    def add_observation(self, cluster, vector, seconds, regions):
        if seconds < 1.2: return
        regions = regions or []
        # Repeated sliding windows must not inflate enrollment duration.
        new_seconds = 0
        for start,end in regions:
            remaining = [(start,end)]
            for old_start,old_end in cluster['coverage']:
                pieces = []
                for a,b in remaining:
                    if old_end <= a or old_start >= b: pieces.append((a,b))
                    else:
                        if a < old_start: pieces.append((a,old_start))
                        if b > old_end: pieces.append((old_end,b))
                remaining = pieces
            new_seconds += sum(b-a for a,b in remaining)
        if cluster['samples'] and new_seconds < .8: return
        observation = {'id':str(uuid.uuid4()),'embedding':vector.tolist(),'seconds':round(new_seconds if regions else seconds,3),'regions':regions}
        cluster['samples'].append(observation)
        cluster['samples'] = cluster['samples'][-12:]
        coverage = sorted(cluster['coverage']+regions)
        merged = []
        for a,b in coverage:
            if merged and a <= merged[-1][1]: merged[-1][1] = max(merged[-1][1],b)
            else: merged.append([a,b])
        cluster['coverage'] = merged
        return observation

    def learn_profile(self, profile, observations):
        templates = profile.get('exemplars') or ([profile['embedding']] if profile.get('embedding') else [])
        anchor = copy.deepcopy(templates[0]) if templates else None
        learned = set(profile.get('learned',[]))
        fresh = [o for o in observations if o.get('id') not in learned]
        vectors = self.profile_vectors(profile)+[unit(o['embedding']) for o in fresh]
        profile['exemplars'] = [v.tolist() for v in (vectors if len(vectors)<=20 else [vectors[0]]+vectors[-19:])]
        if anchor is not None and profile['exemplars']: profile['exemplars'][0] = anchor
        profile['embedding'] = unit(np.mean(vectors,axis=0)).tolist() if vectors else None
        profile['seconds'] = round(profile.get('seconds',0)+sum(o['seconds'] for o in fresh),3)
        profile['learned'] = (list(learned)+[o.get('id') for o in fresh])[-200:]

    def identity_names(self, bank):
        names = {c['id']:f"说话人 {c['number']}" for c in bank['clusters'] if self.canonical(c['id'],bank)==c['id']}
        names.update({p['id']:p['name'] for p in self.profiles})
        return names

    def snapshot_action(self, bank, target_id, source_id):
        before = next((copy.deepcopy(p) for p in self.profiles if p['id']==target_id),None)
        bank['history'].append({'aliases':dict(bank['aliases']),'target':target_id,'before':before,'source':source_id,'globalSourceAlias':self.profile_aliases.get(source_id),'beforeSource':next((copy.deepcopy(p) for p in self.profiles if p['id']==source_id),None),'clusters':copy.deepcopy(bank['clusters'])})
        bank['history'] = bank['history'][-10:]

    def name_or_merge(self, meeting_id, source, name='', target=None, new_person=False):
        bank = self.sessions.get(meeting_id)
        if not bank: raise ValueError('尚未采集到声纹，请先让参会者正常发言。')
        raw_source = source
        source = self.canonical(source,bank)
        cluster = next((c for c in bank['clusters'] if c['id']==source or self.canonical(c['id'],bank)==source),None)
        if source == 'unknown': raise ValueError('该片段尚无可靠声纹，等待更清晰的单人发言后再标记。')
        target_cluster = None
        if target:
            target = self.canonical(target,bank)
            if target == source: raise ValueError('这两个身份已经是同一个人。')
            target_cluster = next((c for c in bank['clusters'] if c['id']==target),None)
            profile = next((p for p in self.profiles if p['id']==target),None)
            if not target_cluster and not profile: raise ValueError('目标人员不存在。')
            source_profile = next((p for p in self.profiles if p['id']==source),None)
            if source_profile and target_cluster:
                # Whichever side the user clicks, keep the established named person.
                source,target = target,source
                cluster = target_cluster; target_cluster = None; profile = source_profile
        else:
            name = name.strip()
            if not name or len(name)>60: raise ValueError('请输入 1–60 个字的姓名。')
            existing = None if new_person else next((p for p in self.profiles if p['id']==source),None)
            target = source if existing else str(uuid.uuid4())
            profile = existing
            if new_person: source = raw_source
        if not cluster and not any(p['id']==source for p in self.profiles): raise ValueError('该匿名说话人样本尚未就绪。')
        self.snapshot_action(bank,target,source)
        if target_cluster:
            baseline = [unit(v['embedding']) for v in target_cluster['samples']]
        else:
            if not profile:
                profile = {'id':target,'name':name,'seconds':0,'exemplars':[],'quarantined':[],'origins':[]}
                self.profiles.append(profile)
            if name: profile['name'] = name
            baseline = self.profile_vectors(profile)
        observations = cluster['samples'] if cluster else [dict(embedding=v.tolist(),seconds=0,regions=[]) for v in self.profile_vectors(next(p for p in self.profiles if p['id']==source))]
        accepted = []; quarantined = []
        for observation in observations:
            vector = unit(observation['embedding'])
            if baseline and max(float(vector@v) for v in baseline)<.4:
                quarantined.append(observation); continue
            accepted.append(observation)
        if target_cluster:
            target_cluster['samples'] = (target_cluster['samples']+accepted)[-12:]
            if cluster: target_cluster['coverage'] += cluster['coverage']
            target_cluster.setdefault('quarantined',[]).extend(quarantined)
        else:
            # Multiple verified exemplars preserve near/far/channel variation rather
            # than replacing the old voice with a single averaged centroid.
            self.learn_profile(profile,accepted)
            profile.setdefault('quarantined',[]).extend(quarantined)
            profile.setdefault('origins',[]).append({'meeting':meeting_id,'cluster':source})
        if source != target: bank['aliases'][source] = target
        if cluster: cluster['confirmed'] = True
        # Merging two named people is explicit: preserve the target, redirect the source.
        if not new_person and source != target and any(p['id']==source for p in self.profiles):
            self.profile_aliases[source] = target
            self.profiles = [p for p in self.profiles if p['id'] != source]
        self.save()
        return {'type':'identity','meetingID':meeting_id,'mappings':dict(self.profile_aliases,**bank['aliases']),'profiles':self.roster(),'learned':len(accepted),'quarantined':len(quarantined),'canUndo':True,'localOnly':new_person,'names':self.identity_names(bank)}

    def undo_identity(self, meeting_id):
        bank = self.sessions.get(meeting_id)
        if not bank or not bank['history']: raise ValueError('没有可撤销的标记或合并。')
        action = bank['history'].pop(); bank['aliases'] = action['aliases']; bank['clusters'] = action['clusters']
        if action.get('globalSourceAlias'): self.profile_aliases[action['source']] = action['globalSourceAlias']
        else: self.profile_aliases.pop(action['source'],None)
        if self.meeting_id == meeting_id: self.unknown = bank['clusters']; self.bank = bank
        self.profiles = [p for p in self.profiles if p['id'] != action['target']]
        if action['before']: self.profiles.append(action['before'])
        if action.get('beforeSource') and action['source'] != action['target']:
            self.profiles = [p for p in self.profiles if p['id'] != action['source']]+[action['beforeSource']]
        self.save()
        return {'type':'identity','meetingID':meeting_id,'mappings':dict(self.profile_aliases,**bank['aliases']),'profiles':self.roster(),'canUndo':bool(bank['history']),'undone':True,'names':self.identity_names(bank)}

    def infer(self, samples, offset=0):
        started = time.perf_counter()
        labels, overlap, probabilities = self.segment(samples)
        identities = []; sources = []
        for k in range(3):
            clean = self.isolated(samples,labels,k,probabilities)
            mask = (labels[:,k] == 1) & (labels.sum(axis=1) == 1) & (probabilities[:,4:].sum(axis=1)<.2) & ((1-probabilities[:,0])>.8)
            regions = [[self.observation_offset+offset+(a*self.shift+self.field/2)/RATE,self.observation_offset+offset+(b*self.shift+self.field/2)/RATE] for a,b in runs(mask) if (b-a)*self.shift/RATE >= .25]
            identities.append(self.match(self.embedding(clean),len(clean)/RATE,regions))
            sources.append(self.last_match_source)
        links = self.bank.setdefault('cannotLinks',[])
        for first in range(3):
            for second in range(first+1,3):
                ids = sorted(set([self.canonical(identities[first][0]),self.canonical(identities[second][0])]))
                if len(ids)==2 and 'unknown' not in ids and np.count_nonzero((labels[:,first]==1)&(labels[:,second]==1))*self.shift/RATE>=.2 and ids not in links: links.append(ids)
        self.coalesce_anonymous()
        identities = [(self.canonical(identity),self.label(identity) if identity!='unknown' else name,score) for identity,name,score in identities]
        events = []; last = None
        for frame in range(len(labels)):
            tracks = tuple(np.where(labels[frame] == 1)[0].tolist())
            key = (tracks,bool(overlap[frame]))
            time_start = offset + (frame*self.shift+self.field/2)/RATE
            time_end = min(offset+len(samples)/RATE,time_start+self.shift/RATE)
            if not tracks: last = None; continue
            names = [identities[k][1] for k in tracks]
            ids = [identities[k][0] for k in tracks]
            score = min(identities[k][2] for k in tracks)
            if last == key and events: events[-1]['end'] = time_end
            else:
                events.append({'start':time_start,'end':time_end,'speakers':names,'speakerIDs':ids,'sourceIDs':[sources[k] for k in tracks],'confidence':round(score,4),'overlap':bool(overlap[frame])})
                last = key
        events = [e for e in events if e['end']-e['start']>=.12]
        return {'type':'turns','mappings':dict(self.profile_aliases,**self.bank['aliases']),'names':self.identity_names(self.bank),'replaceFrom':offset,'end':offset+len(samples)/RATE,'events':events,'inferenceSeconds':round(time.perf_counter()-started,4)}

    def push(self, samples, rate):
        if rate != RATE:
            divisor = math.gcd(rate,RATE); samples = resample_poly(samples,RATE//divisor,rate//divisor)
        self.buffer = np.concatenate([self.buffer,samples])[-self.window:]
        self.total += len(samples)
        if self.total-self.last_inference < 2*RATE: return None
        self.last_inference = self.total
        result = self.infer(self.buffer,(self.total-len(self.buffer))/RATE)
        if time.monotonic()-self.last_saved > 10:
            self.save(); self.last_saved = time.monotonic()
        return result


def main():
    engine = Engine(sys.argv[1],sys.argv[2])
    print(json.dumps({'type':'ready','profiles':engine.roster()}),flush=True)
    for line in sys.stdin:
        request = {}
        try:
            request = json.loads(line)
            command = request['command']
            if command == 'audio':
                result = engine.push(np.frombuffer(base64.b64decode(request['pcm']),dtype='<f4'),int(request['rate']))
            elif command == 'reset': engine.reset(request.get('meetingID',request.get('sessionID','temporary')),request.get('offset',0)); result = {'type':'reset'}
            elif command == 'flush':
                result = engine.infer(engine.buffer,(engine.total-len(engine.buffer))/RATE) if len(engine.buffer) else {'type':'flushed'}
                engine.save()
            elif command == 'replay':
                if request.get('rebuild'):
                    bank = engine.sessions.get(request['meetingID'])
                    if bank:
                        named = {p['id'] for p in engine.profiles}
                        keep = [c for c in bank['clusters'] if c.get('confirmed') or engine.canonical(c['id'],bank) in named]
                        aliases = {source:target for source,target in bank['aliases'].items() if engine.canonical(target,bank) in named}
                        bank['clusters'] = keep; bank['aliases'] = aliases
                        bank['algorithmVersion'] = 2
                engine.reset(request['meetingID'])
                for path in request['paths']:
                    samples = audio(path)
                    for start in range(0,len(samples),RATE):
                        update = engine.push(samples[start:start+RATE],RATE)
                        if update:
                            update['sessionID'] = request['sessionID']
                            print(json.dumps(update,ensure_ascii=False),flush=True)
                if len(engine.buffer):
                    update = engine.infer(engine.buffer,(engine.total-len(engine.buffer))/RATE)
                    update['sessionID'] = request['sessionID']
                    print(json.dumps(update,ensure_ascii=False),flush=True)
                engine.save()
                result = {'type':'replayed','meetingID':request['meetingID'],'sessionID':request['sessionID']}
            elif command == 'contact':
                name = request['name'].strip()
                if not name or len(name)>60: raise ValueError('请输入有效姓名。')
                engine.sessions.setdefault(request['meetingID'],{'clusters':[],'aliases':{},'history':[]})
                person = {'id':str(uuid.uuid4()),'name':name,'seconds':0,'exemplars':[],'quarantined':[],'origins':[]}
                engine.profiles.append(person); engine.save()
                result = {'type':'contact','meetingID':request['meetingID'],'personID':person['id'],'personName':name,'profiles':engine.roster()}
            elif command == 'label':
                result = engine.name_or_merge(request['meetingID'],request['source'],request.get('name',''),request.get('target'),request.get('newPerson',False))
            elif command == 'undo': result = engine.undo_identity(request['meetingID'])
            elif command == 'delete':
                engine.profiles = [p for p in engine.profiles if p['id'] != request['id']]; engine.save()
                result = {'type':'profiles','profiles':engine.roster()}
            else: raise ValueError('未知声纹命令。')
            if result is not None:
                if 'requestID' in request: result['requestID'] = request['requestID']
                if 'sessionID' in request: result['sessionID'] = request['sessionID']
                print(json.dumps(result,ensure_ascii=False),flush=True)
        except Exception as error:
            print(json.dumps({'type':'error','message':str(error),'requestID':request.get('requestID')}),flush=True)

if __name__ == '__main__':
    main()
