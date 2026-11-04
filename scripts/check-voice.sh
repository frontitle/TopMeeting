#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p tests_audio
if [[ ! -f tests_audio/four-speakers-zh.wav ]]; then
    curl -fL --retry 2 https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/0-four-speakers-zh.wav -o tests_audio/four-speakers-zh.wav
fi
shasum -a 256 -c voice_engine/test-fixture.sha256
.voice-runtime/bin/python voice_engine/test_identity_stability.py
.voice-runtime/bin/python voice_engine/test_recordings.py > /tmp/topmeeting-voice-recordings.log
swiftc -parse-as-library Sources/TopMeeting/Feishu.swift Sources/TopMeeting/Board.swift Sources/TopMeeting/Corrections.swift Sources/TopMeeting/VoiceRuntime.swift Sources/TopMeeting/Extensions.swift Sources/TopMeeting/Models.swift Sources/TopMeeting/Gateway.swift Tests/TopMeetingTests/VoiceIPCChecks.swift -o .build/checks/voice-ipc
.build/checks/voice-ipc
