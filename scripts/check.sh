#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/checks
swiftc -parse-as-library Sources/TopMeeting/Extensions.swift Sources/TopMeeting/FeishuStore.swift Sources/TopMeeting/Feishu.swift Sources/TopMeeting/Corrections.swift Sources/TopMeeting/VoiceRuntime.swift Sources/TopMeeting/Models.swift Sources/TopMeeting/Gateway.swift Sources/TopMeeting/Board.swift Sources/TopMeeting/Store.swift Sources/TopMeeting/ContinuousSpeech.swift Sources/TopMeeting/SpeechCapture.swift Sources/TopMeeting/AudioDevices.swift Sources/TopMeeting/AudioSamples.swift Tests/TopMeetingTests/CoreTests.swift -o .build/checks/core
python3 scripts/mock-gateway.py &
MOCK_PID=$!
python3 - <<'PYREADY'
import socket,time
for _ in range(50):
    try:
        with socket.create_connection(('127.0.0.1',19876),timeout=0.1): break
    except OSError: time.sleep(0.05)
else: raise SystemExit('Mock gateway did not start')
PYREADY
trap 'kill "$MOCK_PID" 2>/dev/null || true' EXIT
.build/checks/core
