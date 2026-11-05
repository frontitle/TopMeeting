#!/usr/bin/env python3
"""Inspect Git objects, never the user's untracked meeting data. Print paths, not matching values."""
import argparse
import re
import subprocess
import sys
from pathlib import PurePosixPath

ROOT_FILES = {'LICENSE','NOTICE','Package.swift','CONTRIBUTING.md','README.md','README.zh-CN.md','SECURITY.md','THIRD_PARTY_NOTICES.md','.gitignore'}
ROOT_DIRS = {'.github','.githooks','apps','Sources','Tests','docs','localization','packages','schemas','scripts','voice_engine'}
PRIVATE_DIRS = {'.build', 'dist', 'reports', 'tests_audio', 'node_modules', 'coverage',
                '.voice-runtime', '.feishu-runtime', '.voice-venv', '__pycache__'}
PRIVATE_NAMES = {'credentials.bin','document-accounts.bin','meetings.json','meetings.previous.json',
                 'voice-profiles.json','people.json','recognition-terms.json','.meeting-write.lock'}
PRIVATE_SUFFIXES = {'.caf','.wav','.m4a','.mp3','.webm','.flac','.mp4','.mov','.onnx',
                    '.pem','.pfx','.p12','.key','.sqlite','.db','.log','.zip','.exe','.dmg','.tmp'}
SIGNATURES = {
    'private key': rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----',
    'provider credential': rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-(?:proj-)?[A-Za-z0-9_-]{32,}|AKIA[A-Z0-9]{16})',
    'private endpoint': rb'(?<![\w.])(?:192\.168\.\d{1,3}\.\d{1,3}|100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3})(?![\w.])',
    'personal home directory': rb'(?:/Users/|C:\\\\Users\\\\)[A-Za-z0-9_.-]+[/\\]',
}
ASSETS = {'apps/windows/src/logo.png'}
LEGACY_ASSETS = {'apps/windows/build/icon.png'}

def git(*args):
    return subprocess.check_output(['git', *args])

def entries(revision):
    raw = git('ls-files','--stage','-z') if revision is None else git('ls-tree','-r','-z',revision)
    for entry in raw.split(b'\0'):
        if not entry: continue
        meta,name=entry.split(b'\t',1)
        fields=meta.split()
        yield name.decode(), fields[1 if revision is None else 2].decode(), fields[0]

def check(revisions, history):
    errors=set()
    inspected={}
    for revision in revisions:
        for name,oid,mode in entries(revision):
            path=PurePosixPath(name)
            if not (name in ROOT_FILES or (history and name=='README.en.md') or (len(path.parts)>1 and path.parts[0] in ROOT_DIRS)):
                errors.add((name,'unreviewed top-level path'))
                continue
            if mode not in (b'100644',b'100755'):
                errors.add((name,'unexpected link or submodule'))
                continue
            if (PRIVATE_DIRS.intersection(path.parts) or path.name in PRIVATE_NAMES or path.suffix.lower() in PRIVATE_SUFFIXES
                    or (path.name.startswith('.env') and path.name!='.env.example') or 'unreadable-' in path.name
                    or name.startswith(('apps/windows/runtime/','apps/windows/release/','voice_engine/models/'))):
                errors.add((name,'local data or build artifact'))
                continue
            asset = name in ASSETS or (history and name in LEGACY_ASSETS)
            key=(oid,asset)
            if key not in inspected:
                size=int(git('cat-file','-s',oid))
                problems=[]
                if size > (4_000_000 if asset else 2_000_000):
                    problems.append('oversized Git object')
                else:
                    blob=git('cat-file','blob',oid)
                    if asset:
                        if not blob.startswith(b'\x89PNG\r\n\x1a\n'): problems.append('invalid icon format')
                    elif b'\0' in blob:
                        problems.append('unexpected binary')
                    else:
                        problems.extend(label for label,pattern in SIGNATURES.items() if re.search(pattern,blob))
                inspected[key]=problems
            errors.update((name,reason) for reason in inspected[key])
    for name,reason in sorted(errors): print(f'{name}: {reason}',file=sys.stderr)
    if errors: raise SystemExit('Source review failed')
    print(f'Checked {len(inspected)} unique source objects across {len(revisions)} snapshot(s).')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    group=parser.add_mutually_exclusive_group()
    group.add_argument('--index',action='store_true')
    group.add_argument('--history',metavar='REVISION')
    group.add_argument('--rev',default='HEAD')
    a=parser.parse_args()
    revisions=git('rev-list',a.history).decode().split() if a.history else [None if a.index else a.rev]
    check(revisions,bool(a.history))
