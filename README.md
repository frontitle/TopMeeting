# TopMeeting

[简体中文](README.zh-CN.md) · [Windows download](https://github.com/frontitle/TopMeeting/releases/tag/windows-v0.14.0-preview.1) · [Contributing](CONTRIBUTING.md)

TopMeeting is a local-first meeting assistant for macOS and Windows with **real-time speech-to-text and offline speaker diarization**. Put one microphone on the table and follow a conversation as an editable, speaker-attributed transcript.

- **Name a voice as you go.** On-device speaker embeddings group turns before anyone enrolls. Name an anonymous speaker, reuse a known identity, or merge a mistaken split. The voice profiles stay on your device.
- **Review interruptions.** Local overlap detection flags likely simultaneous speech for review. A timestamped paragraph can list multiple participants. Accuracy varies with microphone placement and room noise.
- **Choose what leaves the device.** Local transcription works without a paid transcription API. Connect your own OpenClaw or compatible LLM for summaries, or bind a document workspace to create a meeting link when recording starts.

| | macOS | Windows x64 |
|---|---|---|
| Live captions | Apple Speech, with continuous transcription on supported macOS 26+ devices | Local Chinese/English streaming model |
| Speakers | Automatic discovery, naming, identity merging and overlap detection | Shared local speaker engine, editable paragraph participants |
| Listening window | Draggable, pause/resume, elapsed time, double-click to reopen | Same controls in a floating desktop window |
| Meeting documents | Start-of-meeting document links. Feishu also supports transcript, recording and final board delivery | Start-of-meeting document links |
| Interface | Simplified Chinese and English | Simplified Chinese |

**Start a meeting.** Create a meeting, then choose **Start recording**. On Windows, the first click checks the speech models before asking for microphone access. Download approximately 220 MB once for offline transcription, or choose audio-only recording to save the original audio immediately. Click Start again after the download to begin recording.

**Connect a document account.** Under Settings → Extensions, choose a single destination (Feishu, DingTalk, Tencent Docs, Google Docs or Notion), bind your account and enable automatic creation. Recording starts a document for that meeting. Open it from the meeting workspace. An uncertain creation result stays available for manual reconciliation so that restarting a meeting does not duplicate documents.

**Generate notes.** Select a configured model provider to summarize on demand or after recording ends. Equivalent requests reuse saved notes. A failed request preserves the previous notes. Local live transcription requires no paid ASR service.

## Install and build

The Windows prerelease includes an unsigned per-user installer and a ZIP. Windows may display an unknown-publisher prompt. See the [Windows guide](apps/windows/README.md) for installation, model setup and document permissions.

The macOS development target is macOS 15 or later. Build using Swift 6 and a macOS 26+ SDK. Build prerequisites include uv, Python 3.13 for the voice setup script, and npm for Feishu CLI. Packaging downloads a relocatable CPython and a checksum-pinned official Node.js binary for the build Mac’s architecture.

```sh
swift build -c release
./scripts/setup-voice.sh
./scripts/setup-feishu.sh
./scripts/build-app.sh
```

The ad-hoc signed development application is written to `dist/TopMeeting.app`. The bundle includes the Python standard library, voice wheels and Node.js. End users do not need Homebrew, Python or Node.js. The build checks native library paths before signing.

## Data and integrations

Meeting files, source recordings and voice profiles stay on the device. Model summaries and assistant conversations send relevant text to the selected provider. Automatic document creation sends the meeting title to the selected account. macOS Feishu delivery can send content and original recordings when enabled. See [Security](SECURITY.md) for storage and disclosure details.

Meeting saves retain the previous valid snapshot. If the primary file is unreadable, recovery preserves the damaged copy before restoring a valid backup. An unreadable library with no usable backup requires manual recovery.

## Project layout

| Path | Responsibility |
|---|---|
| `Sources/TopMeeting` | Native macOS capture, speech, meeting library and workspace |
| `apps/windows` | Electron desktop host, local audio capture, speech worker and packaging |
| `voice_engine` | Shared speaker identification and overlap detection |
| `packages/documents` | Provider APIs, OAuth handling and macOS document bridge |
| `packages/core` | Portable search, transcript changes and evidence-checked summary operations |
| `Tests`, `scripts`, `.github/workflows` | Regression tests, build tools and release checks |

[Architecture](docs/ARCHITECTURE.md), [roadmap](docs/ROADMAP.md), [testing and contribution instructions](CONTRIBUTING.md) and [third-party notices](THIRD_PARTY_NOTICES.md) describe the implementation and its limits. Voice attribution can be uncertain, especially during overlapping or distant speech. The project currently provides macOS and Windows clients.
