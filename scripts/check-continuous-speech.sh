#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/checks
swiftc -parse-as-library Sources/TopMeeting/ContinuousSpeech.swift Sources/TopMeeting/AudioSamples.swift Tests/TopMeetingTests/ContinuousSpeechChecks.swift -o .build/checks/continuous-speech
.build/checks/continuous-speech "$@"
