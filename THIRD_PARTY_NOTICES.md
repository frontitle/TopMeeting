# Third-party notices

TopMeeting's Apache-2.0 license applies to its original code, not to external models, datasets or vendor services.

| Component | Source and license handling |
|---|---|
| Apple Speech / AppKit / SwiftUI | System SDKs; not redistributed as open-source TopMeeting code. |
| sherpa-onnx | Apache-2.0 project; retain distribution notices. The powerset segmentation mapping follows the MIT-licensed Python example, copyright Xiaomi Corp., Fangjun Kuang (2024). See `voice_engine/THIRD_PARTY.md`. |
| pyannote segmentation model | Upstream model license is downloaded and bundled beside the ONNX file. See `voice_engine/THIRD_PARTY.md`. |
| WeSpeaker CN-Celeb embedding model | Downloaded separately. Upstream model and dataset conditions require review before distributing weights; an Apache-licensed application does not relicense weights. |
| ONNX Runtime, NumPy, SciPy, SoundFile | Dependency versions are pinned in `voice_engine/requirements.lock.txt`; preserve the licenses contained in wheel distributions. |
| Feishu/Lark CLI | `@larksuite/cli`; the installed CLI's MIT LICENSE is included by `scripts/build-app.sh`. |

Windows ships the CPython embeddable runtime (including its license) and the pinned wheels with their distribution metadata. Speech models are downloaded separately from their upstream publishers. macOS bundles CPython from the uv-managed python-build-standalone distribution (see VoiceRuntime/lib/python3.13/LICENSE.txt), the pinned voice wheels with their notices, and an official Node.js binary with DocumentsRuntime/NODE-LICENSE. Electron/Chromium retain the notices included in the Windows distribution.

Reference projects requested during design: [Backchannel](https://github.com/talberthoule/backchannel) and [meeting-minutes-pro](https://github.com/JerryWoo/meeting-minutes-pro). Referencing their product ideas is not a blanket grant to redistribute their code. Any future imported code must retain its original license and attribution.

The repository excludes recordings, voice profiles, downloaded model weights and local diagnostic transcripts. A signed binary release requires a separate model/runtime redistribution review; no public binary release is performed by the local build script.
