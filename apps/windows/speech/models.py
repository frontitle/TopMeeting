"""Install verified upstream weights on the user's device. No audio leaves this process."""
import hashlib
import shutil
import tarfile
import tempfile
import urllib.request
from pathlib import Path

ASR = "https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/resolve/98590b7ed6443e77b714204da2757d75e1a642f4/"
RELEASE = "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
SEGMENT = "sherpa-onnx-pyannote-segmentation-3-0"
FILES = {
    "tokens.txt": ("a8e0e4ec53810e433789b54a5c0134a7eaa2ffca595a6334d54c00da858841d3", ASR + "tokens.txt"),
    "encoder-epoch-99-avg-1.int8.onnx": ("8fa764187a261844f859d7143ebaa563af5d10adfece4c18a8f414c88cba2a9b", ASR + "encoder-epoch-99-avg-1.int8.onnx"),
    "decoder-epoch-99-avg-1.int8.onnx": ("1a70c593d71e53f023f5f55b0b4cfff5055abb786ee3992e5f63dc2e273cc4fa", ASR + "decoder-epoch-99-avg-1.int8.onnx"),
    "joiner-epoch-99-avg-1.int8.onnx": ("1ed689c5ed19dbaa725d9d191bb4822b5f4855a39e1ffd28cbc1f340d25b2ee0", ASR + "joiner-epoch-99-avg-1.int8.onnx"),
    "embedding.onnx": ("f86cd6c509f331f0e20b07bd48d1b2eb7de54202643401c4e84695ac861a0e5a", RELEASE + "speaker-recongition-models/wespeaker_zh_cnceleb_resnet34.onnx"),
    SEGMENT + "/model.onnx": ("220ad67ca923bef2fa91f2390c786097bf305bceb5e261d4af67b38e938e1079", RELEASE + "speaker-segmentation-models/" + SEGMENT + ".tar.bz2"),
}

def valid(path, digest):
    if not path.is_file():
        return False
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest() == digest

def install(root, progress=lambda count,total: None):
    root.mkdir(parents=True, exist_ok=True)
    for count,(name,(digest,url)) in enumerate(FILES.items()):
        progress(count,len(FILES))
        target = root / name
        if valid(target, digest):
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=root) as work:
            downloaded = Path(work) / "download"
            with urllib.request.urlopen(url, timeout=60) as incoming, downloaded.open("wb") as out:
                shutil.copyfileobj(incoming, out)
            if name.startswith(SEGMENT + "/"):
                with tarfile.open(downloaded) as archive:
                    for member in [name, SEGMENT + "/LICENSE"]:
                        entry = archive.getmember(member)
                        if not entry.isfile() or entry.size > 100_000_000:
                            raise ValueError("Invalid segmentation archive")
                        with archive.extractfile(entry) as src, (Path(work) / Path(member).name).open("wb") as dest:
                            shutil.copyfileobj(src, dest)
                downloaded = Path(work) / "model.onnx"
                (Path(work) / "LICENSE").replace(target.parent / "LICENSE")
            if not valid(downloaded, digest):
                raise ValueError("Model checksum mismatch: " + name)
            downloaded.replace(target)
    progress(len(FILES),len(FILES))
