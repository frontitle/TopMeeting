"""Offline streaming transcription and acoustic identity matching over local stdin/stdout."""
import base64
import json
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from models import FILES, install, valid

def emit(event):
    print(json.dumps(event, ensure_ascii=True), flush=True)

class Session:
    def __init__(self, root, profiles, meeting, offset):
        import sherpa_onnx
        from engine import Engine
        self.voice = Engine(root, profiles)
        self.voice.reset(meeting, offset)
        self.recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
            tokens=str(root / "tokens.txt"),
            **{k: str(root / (k + "-epoch-99-avg-1.int8.onnx")) for k in ["encoder", "decoder", "joiner"]},
            enable_endpoint_detection=True, rule2_min_trailing_silence=2.2,
            rule3_min_utterance_length=45, provider="cpu", num_threads=2)
        self.stream = self.recognizer.create_stream()
        self.time = self.start = 0.0
        self.offset = offset
        self.partial = ""
        self.turns = []
        self.recent = []
        self.seen = set()
        self.roster = []

    def update_turns(self, update):
        if update:
            boundary = update["replaceFrom"]
            self.turns = [dict(t,end=min(t["end"],boundary)) for t in self.turns
                          if t["end"] > self.time-70 and t["start"] < boundary] + update["events"]
            for turn in update["events"]:
                self.seen.update(turn["speakerIDs"])
            self.seen.update(c["id"] for c in self.voice.bank["clusters"])
            ids = dict.fromkeys(self.voice.canonical(key) for key in sorted(self.seen) if key != "unknown")
            named = {p["id"] for p in self.voice.profiles}
            roster = [{"id":key,"name":self.voice.label(key),"named":key in named} for key in ids]
            if roster != self.roster:
                self.roster = roster
                emit({"type":"roster","speakers":roster})
            self.recent = [p for p in self.recent if p["end"] >= boundary]
            for paragraph in self.recent:
                assignment = self.speaker(paragraph["start"],paragraph["end"])
                if assignment != paragraph["assignment"]:
                    paragraph["assignment"] = assignment
                    emit({"type":"attribution","start":paragraph["start"]+self.offset,**assignment})

    def speaker(self, start, end):
        scores = defaultdict(float)
        overlap = 0
        simultaneous = defaultdict(float)
        for turn in self.turns:
            duration = max(0, min(end, turn["end"]) - max(start, turn["start"]))
            if turn["overlap"]:
                overlap += duration
                for identity in turn["speakerIDs"]:
                    simultaneous[self.voice.canonical(identity)] += duration
            else:
                for identity in turn["speakerIDs"]:
                    scores[self.voice.canonical(identity)] += duration
        best = max(scores, key=scores.get) if scores else "unknown"
        if scores.get(best, 0) < .25:
            best = "unknown"
        contributors = [identity for identity in dict.fromkeys([best, *scores, *simultaneous])
                        if identity != "unknown" and (identity == best or scores[identity] >= .65 or simultaneous[identity] >= .45)]
        return {"speakerID": best, "speaker": self.voice.label(best), "overlap": overlap >= .25,
                "voices": [{"id":identity, "name":self.voice.label(identity)} for identity in contributors]}

    def decode(self):
        while self.recognizer.is_ready(self.stream):
            self.recognizer.decode_stream(self.stream)
        return self.recognizer.get_result(self.stream).strip()

    def finalize(self, text):
        if text:
            if self.voice.total != self.voice.last_inference:
                self.update_turns(self.voice.infer(self.voice.buffer, (self.voice.total-len(self.voice.buffer))/16000))
            assignment = self.speaker(self.start,self.time)
            self.recent.append({"start":self.start,"end":self.time,"assignment":assignment})
            emit({"type":"final","text":text,"start":self.start+self.offset,"end":self.time+self.offset,**assignment})
        self.recognizer.reset(self.stream)
        self.start = self.time
        self.partial = ""

    def push(self, samples):
        import numpy as np
        self.update_turns(self.voice.push(samples, 16000))
        self.time += len(samples)/16000
        peak = float(np.max(np.abs(samples))) if len(samples) else 0
        # Peak-limited gain only affects speech recognition. Voice embeddings use raw PCM.
        self.stream.accept_waveform(16000, samples * min(3.0, .96 / max(.001, peak)))
        text = self.decode()
        if self.recognizer.is_endpoint(self.stream):
            self.finalize(text)
        elif text != self.partial:
            self.partial = text
            emit({"type":"partial","text":text,**self.speaker(max(self.start,self.time-2), self.time)})

    def finish(self):
        import numpy as np
        self.stream.accept_waveform(16000, np.zeros(9600, dtype=np.float32))
        self.stream.input_finished()
        self.finalize(self.decode())
        self.voice.save()

def main():
    mode, directory, profiles, *args = sys.argv[1:]
    root = Path(directory)
    if mode == "install":
        install(root)
        return
    if not all(valid(root/name,digest) for name,(digest,_) in FILES.items()):
        raise ValueError("请先在设置中下载或修复本地语音模型")
    if mode == "name":
        from engine import Engine
        engine=Engine(root, profiles)
        engine.reset(args[0])
        result=engine.name_or_merge(args[0],args[1],args[2],target=args[3] if len(args)>3 else None)
        emit(result)
        return
    import numpy as np
    session = Session(root, profiles, args[0], float(args[1]))
    emit({"type":"ready"})
    for line in sys.stdin:
        request = json.loads(line)
        if request["cmd"] == "finish":
            session.finish()
            emit({"type":"finished"})
            return
        if request["cmd"] == "name":
            try:
                emit(session.voice.name_or_merge(args[0],request["source"],request["name"],target=request.get("target")))
            except ValueError as error:
                emit({"type":"identityError","message":str(error)})
        else:
            samples = np.frombuffer(base64.b64decode(request["pcm"],validate=True), dtype="<f4")
            if not 0 < len(samples) <= 16000 or not np.all(np.isfinite(samples)):
                raise ValueError("Invalid audio")
            session.push(samples)
            emit({"type":"ack"})

if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        emit({"type":"error","message":str(error)})
        sys.exit(1)
