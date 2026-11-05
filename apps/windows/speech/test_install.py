import hashlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import models

class InstallTests(unittest.TestCase):
    def test_interrupted_install_reuses_verified_files(self):
        files={name:(hashlib.sha256(name.encode()).hexdigest(),name) for name in ['one','two']}
        with tempfile.TemporaryDirectory() as tmp, patch.object(models,'FILES',files):
            root=Path(tmp)
            with patch('urllib.request.urlopen',side_effect=[io.BytesIO(b'one'),OSError('offline')]):
                with self.assertRaises(OSError): models.install(root)
            self.assertTrue((root/'one').is_file())
            self.assertFalse((root/'two').exists())
            with patch('urllib.request.urlopen',return_value=io.BytesIO(b'two')) as source:
                models.install(root)
                source.assert_called_once_with('two',timeout=60)
            self.assertTrue(all(models.valid(root/name,digest) for name,(digest,_) in files.items()))
if __name__=='__main__':
    unittest.main()
