#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
PYTHON_BIN=${TOPMEETING_PYTHON:-/opt/homebrew/bin/python3.13}
"$PYTHON_BIN" -m venv .voice-runtime
.voice-runtime/bin/pip install -r voice_engine/requirements.lock.txt
mkdir -p voice_engine/models
curl -fL --retry 2 https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2 -o voice_engine/models/segmentation.tar.bz2
tar -xjf voice_engine/models/segmentation.tar.bz2 -C voice_engine/models
curl -fL --retry 2 https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/wespeaker_zh_cnceleb_resnet34.onnx -o voice_engine/models/embedding.onnx
shasum -a 256 -c voice_engine/model-checksums.txt
