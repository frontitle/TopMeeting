# Local voice models and runtime

- Segmentation: pyannote/segmentation-3.0, converted ONNX release from k2-fsa/sherpa-onnx. MIT, copyright CNRS. Its LICENSE is bundled alongside model.onnx.
  - https://huggingface.co/pyannote/segmentation-3.0
  - https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-segmentation-models
- Speaker embeddings: wespeaker_zh_cnceleb_resnet34.onnx, provided in sherpa-onnx speaker-recongition-models release. Chinese CN-Celeb speaker-verification checkpoint. Do not assume the application license replaces upstream code/model/data conditions.
  - https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-recongition-models
  - https://github.com/wenet-e2e/wespeaker
- Runtime: sherpa-onnx, ONNX Runtime, NumPy, SciPy and SoundFile. Exact installed versions are pinned in requirements.lock.txt; their wheel metadata contains their upstream licenses.
- The seven-class powerset mapping follows the MIT-licensed sherpa-onnx Python segmentation example (Xiaomi Corp., Fangjun Kuang, 2024). The surrounding incremental/profile/IPC implementation is specific to TopMeeting.
  - https://github.com/k2-fsa/sherpa-onnx/blob/master/scripts/pyannote/segmentation/speaker-diarization-onnx.py
- Test real speech: 0-four-speakers-zh.wav from the official sherpa-onnx segmentation-model release. Not bundled or redistributed with the application. A controlled overlap test mixes two held-out segments from this recording; it is not a recording of a live argument.

Audio processing, profiles and inference stay on this Mac. No voice biometric data is sent to OpenClaw. Only speaker-attributed meeting text is used in the existing text-analysis route.
