"""Check native dependencies for this Mac's architecture before publishing a bundle."""
import argparse
import ctypes
import json
import platform
import re
import subprocess
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("app", type=Path)
parser.add_argument("--strip-build-rpaths", action="store_true")
args = parser.parse_args()
app = args.app.resolve()
resources = app / "Contents/Resources"
voice = resources / "VoiceRuntime"
magic = {bytes.fromhex(h) for h in ("feedface", "cefaedfe", "feedfacf", "cffaedfe",
                                    "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}
system = ("/usr/lib/", "/System/Library/")
cache_contains = ctypes.CDLL(None)._dyld_shared_cache_contains_path
cache_contains.argtypes = [ctypes.c_char_p]
cache_contains.restype = ctypes.c_bool
count = 0
for path in app.rglob("*"):
    if path.is_symlink():
        if path.readlink().is_absolute() or not path.resolve().is_relative_to(app) or not path.exists():
            raise SystemExit(f"Broken or external symlink: {path}")
        continue
    if not path.is_file():
        continue
    with path.open("rb") as file:
        if file.read(4) not in magic:
            continue
    count += 1
    output = subprocess.check_output(["otool", "-arch", platform.machine(), "-l", path], text=True)
    if "LC_SEGMENT_64" not in output:
        raise SystemExit(f"Missing native architecture: {path}")
    commands = re.findall(r"^\s+cmd (LC_\w+)\n\s+cmdsize \d+\n\s+(?:path|name) (.+?) \(offset",output,re.M)
    executable_dir = voice / "bin" if path.is_relative_to(voice) else path.parent
    def expand(value):
        return Path(value.replace("@loader_path", str(path.parent))
                         .replace("@executable_path", str(executable_dir))).resolve()
    rpaths = []
    removed = []
    for cmd, value in commands:
        if cmd != "LC_RPATH":
            continue
        if expand(value).is_relative_to(app) or value.startswith(system):
            rpaths.append(expand(value))
        elif args.strip_build_rpaths:
            removed.append(value)
        else:
            raise SystemExit(f"External runpath in {path.name}: {value}")
    for cmd, value in commands:
        if cmd in ("LC_ID_DYLIB", "LC_RPATH") or value.startswith(system):
            continue
        candidates = ([base / value.removeprefix("@rpath/") for base in rpaths]
                      if value.startswith("@rpath/") else [expand(value)])
        if not any((file.is_relative_to(app) and file.is_file()) or
                   (str(file).startswith(system) and cache_contains(bytes(file))) for file in candidates):
            raise SystemExit(f"Unresolved dependency in {path}: {value}")
    if removed:
        flags = [arg for value in removed for arg in ("-delete_rpath", value)]
        subprocess.run(["install_name_tool", *flags, path], check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", path], check=True)
# Exercise imports and dlopen calls which are invisible to the Mach-O load commands.
with tempfile.TemporaryDirectory() as temp:
    env = {"PATH": "/usr/bin:/bin", "TMPDIR": temp}
    def run(args, payload):
        result = subprocess.run(args, cwd=temp, env=env, input=payload, text=True,
                                capture_output=True, timeout=90)
        if result.returncode:
            raise SystemExit(result.stderr or f"{args[0]} exited with {result.returncode}")
        return json.loads(result.stdout)

    engine = resources / "voice_engine"
    ready = run([voice / "bin/python3", "-I", "-B", "-u", engine / "engine.py",
                 engine / "models", Path(temp) / "profiles.json"], "")
    if ready.get("type") != "ready":
        raise SystemExit("Voice engine did not load the bundled models")
    docs = resources / "DocumentsRuntime"
    response = run([docs / "node", docs / "macos-bridge.cjs"], '{"action":"smoke"}')
    if response.get("error") != "未知文档操作":
        raise SystemExit("Document bridge did not handle the offline probe")
print(f"Verified dependencies of {count} native binaries ({platform.machine()})")
