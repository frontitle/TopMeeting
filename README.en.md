# TopMeeting

[简体中文](README.md) · [Contributing](CONTRIBUTING.md) · [Architecture](docs/ARCHITECTURE.md)

A native macOS meeting assistant with local recordings, live transcription, speaker identification, editable transcripts and structured summaries. Original project code is licensed under Apache-2.0. Current development version: **0.11.0**.

## Windows preview

[Download the Windows x64 installer or ZIP](https://github.com/frontitle/TopMeeting/releases/tag/windows-v0.12.0-preview.1). This preview supports recording, playback, editable transcripts and model summaries. Transcription requires a separately configured service; voiceprints, live overlay and Feishu are not ported yet. See [Windows scope](apps/windows/README.md).

## Features

- Chinese and English primary UI; selectable supported transcription language and independent summary language.
- Continuous on-device SpeechAnalyzer transcription on supported macOS 26+ systems, with a legacy Speech fallback.
- Compact draggable listening window with pause/resume, elapsed time, audio waveform and double-click navigation.
- Automatic voice discovery during meetings, searchable speaker naming and manual identity merging. Uncertain identities remain unconfirmed. Overlap detection does not separate mixed speech.
- Complete finalized transcript paragraphs, word corrections and contextual hints; meeting assistant conversation.
- Date groups, status filters, cross-field keyword search, deletion and recovery.
- On-demand summaries and one final summary after recording, with duplicate-request protection. Requests currently include a full meeting snapshot.
- Extensions settings for remote OpenClaw, OpenAI-compatible model APIs and Feishu document delivery. Credentials use separate Keychain entries. API billing is independent of subscription access.

## Development

Use Swift 6 and a macOS 26+ SDK. Deployment target is macOS 15; modern speech support depends on the device and installed language assets.

```sh
swift build -c release
./scripts/check.sh
node --test packages/core/test/core.test.js
./scripts/setup-voice.sh
./scripts/setup-feishu.sh
./scripts/build-app.sh
```

The development bundle is `dist/TopMeeting.app`, ad-hoc signed. Its voice runtime still depends on a local Python 3.13 framework; it is not a standalone public installer. Tests use synthetic fixtures and a local mock gateway, without live model charges.

Configure providers under Settings → Extensions. OpenClaw runs remotely and requires its HTTP Chat Completions endpoint; the client does not embed it or extract browser credentials. Account eligibility and quotas are controlled by the provider.

Meeting data lives in `~/Library/Application Support/TopMeeting/`. Summary/chat requests send relevant text to the selected provider. Enabled Feishu delivery sends document content and selected recordings. See [Security](SECURITY.md) and [Third-party notices](THIRD_PARTY_NOTICES.md).

## Platform status

The native macOS client is joined by a [Windows 0.12.0 preview](apps/windows/README.md) with recording, editable transcripts and model summaries. Windows does not yet include local live transcription, voiceprints or Feishu. `packages/core` contains portable search, transcript-delta and evidence-checked summary-patch primitives, with a Windows/macOS/Linux CI configuration. It does not yet replace native Swift business logic. Windows feature parity, a Web client, DingTalk/Slack connectors, automatic incremental summaries, project categories and indexed search are planned. Feishu cloud delivery still needs live acceptance testing.

See [Architecture](docs/ARCHITECTURE.md), [Roadmap](docs/PRODUCT-ROADMAP.zh-CN.md), [LICENSE](LICENSE) and [NOTICE](NOTICE). Third-party code and model assets retain their own licenses.
