"""Exercise the release guard on a throwaway Git history containing synthetic data."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

GUARD=Path(__file__).resolve().parents[2]/'scripts/check-source.py'

class SourceGuardTests(unittest.TestCase):
    def test_index_and_reachable_history(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            def run(*args):
                return subprocess.run(args,cwd=root,capture_output=True,text=True)
            def git(*args):
                run('git',*args).check_returncode()
            git('init','-q')
            git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid')
            (root/'README.md').write_text('Synthetic project')
            git('add','README.md')
            run(sys.executable,str(GUARD),'--index').check_returncode()
            secret='gh'+'p_'+'X'*36
            (root/'README.md').write_text(secret)
            git('add','README.md')
            failed=run(sys.executable,str(GUARD),'--index')
            self.assertNotEqual(failed.returncode,0)
            self.assertNotIn(secret,failed.stdout+failed.stderr)
            git('commit','-qm','synthetic credential')
            (root/'README.md').write_text('Clean again')
            git('commit','-qam','clean tip')
            run(sys.executable,str(GUARD),'--rev','HEAD').check_returncode()
            self.assertNotEqual(run(sys.executable,str(GUARD),'--history','HEAD').returncode,0)
            (root/'recording.caf').write_text('fixture')
            git('add','recording.caf')
            self.assertNotEqual(run(sys.executable,str(GUARD),'--index').returncode,0)

if __name__=='__main__':
    unittest.main()
