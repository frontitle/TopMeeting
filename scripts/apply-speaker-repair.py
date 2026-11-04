#!/usr/bin/env python3
"""Apply a locally validated acoustic replay after TopMeeting has closed.

Preserves text, recordings, other meetings, named profiles and recovery copies.
The expected snapshot prevents overwriting newer acoustic/human identity work.
"""
import argparse,copy,datetime,json,os,pathlib,shutil,subprocess

parser=argparse.ArgumentParser()
parser.add_argument('--meeting',required=True)
parser.add_argument('--expected',type=pathlib.Path,required=True)
parser.add_argument('--profiles',type=pathlib.Path,required=True)
parser.add_argument('--timeline',type=pathlib.Path,required=True)
parser.add_argument('--root',type=pathlib.Path,default=pathlib.Path.home()/'Library/Application Support/TopMeeting')
parser.add_argument('--check-only',action='store_true')
args=parser.parse_args()
root=args.root
original=json.loads((root/'meetings.json').read_text())
voices=json.loads((root/'voice-profiles.json').read_text())
expected=json.loads(args.expected.read_text())
old=next(m for m in expected if m['id']==args.meeting)
meeting=next(m for m in original if m['id']==args.meeting)
for field in ['voiceTurns','voiceAliases','audioSegments','duration']:
    if meeting.get(field)!=old.get(field):raise SystemExit('Meeting identity/audio changed after diagnosis; rerun comparison before applying.')
fixed=json.loads(args.profiles.read_text());bank=copy.deepcopy(fixed['sessions'][args.meeting])
timeline=json.loads(args.timeline.read_text());aliases=dict(voices.get('profileAliases',{}),**bank['aliases'])
def canonical(identity):
    seen=set()
    while identity in aliases and identity not in seen:seen.add(identity);identity=aliases[identity]
    return identity
ids={canonical(identity) for turn in timeline for identity in turn.get('sourceIDs',turn['speakerIDs']) if identity!='unknown'}
if len(ids)!=3:raise SystemExit('Validated replay must contain the three reviewed canonical identities.')
# This assertion validates this incident artifact, not a participant cap in the engine.
updated=copy.deepcopy(original);result=next(m for m in updated if m['id']==args.meeting)
names={c['id']:f"说话人 {c['number']}" for c in bank['clusters'] if canonical(c['id'])==c['id']}
names.update({p['id']:p['name'] for p in voices['profiles']})
manual_ids={line.get('personID') for line in meeting.get('lines',[])}
names.update({k:v for k,v in (meeting.get('voiceNames') or {}).items() if k in manual_ids or k.startswith('name:')})
result.update(voiceTurns=timeline,voiceAliases=aliases,voiceNames=names,canUndoIdentity=bool(bank['history']))
if result.get('notes'):result['summaryState']='retry'
new_voices=copy.deepcopy(voices);bank['algorithmVersion']=2;new_voices['sessions'][args.meeting]=bank
assert result['lines']==meeting['lines']
assert result.get('audioSegments')==meeting.get('audioSegments')
assert new_voices['profiles']==voices['profiles']
assert [m for m in updated if m['id']!=args.meeting]==[m for m in original if m['id']!=args.meeting]
print('Validated replay:',len(ids),'canonical speakers;',len(result['lines']),'transcript segments unchanged')
if args.check_only:raise SystemExit(0)
if subprocess.run(['pgrep','-x','TopMeeting'],stdout=subprocess.DEVNULL).returncode==0:
    raise SystemExit('Close TopMeeting before applying the repair.')
backup=root/'Recovery'/datetime.datetime.now().strftime('%Y%m%d-%H%M%S-speakers')
backup.mkdir(parents=True,mode=0o700);backup.parent.chmod(0o700)
for name in ['meetings.json','voice-profiles.json','people.json']:
    if (root/name).exists():shutil.copy2(root/name,backup/name);(backup/name).chmod(0o600)
def replace(name,value):
    temp=root/(name+'.repair-tmp')
    with temp.open('w') as f:
        temp.chmod(0o600);json.dump(value,f,ensure_ascii=False);f.flush();os.fsync(f.fileno())
    os.replace(temp,root/name)
try:
    replace('voice-profiles.json',new_voices);replace('meetings.json',updated)
except BaseException:
    for name in ['meetings.json','voice-profiles.json']:shutil.copy2(backup/name,root/name)
    raise
assert json.loads((root/'meetings.json').read_text())==updated
assert json.loads((root/'voice-profiles.json').read_text())==new_voices
print('Applied with recovery copies:',backup)
