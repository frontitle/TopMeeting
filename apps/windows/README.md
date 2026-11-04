# TopMeeting Windows preview 0.12.0

Windows x64 preview, built with Electron. This is a separate client, not a recompiled Swift application.

Implemented: microphone recording with pause/resume, original WebM/Opus files, local meeting persistence, title/transcript/context editing, manual speaker names, search, deletion/restoration, Markdown export, remote OpenClaw and OpenAI-compatible streamed summaries with unchanged-input deduplication. Interrupted model responses preserve the previous summary. Credentials are encrypted with Electron safeStorage (Windows DPAPI). Each recording chunk is saved every five seconds.

Optional post-meeting transcription uses a configured `audio/transcriptions` service. Audio is uploaded only when the user clicks Transcribe. The preview enforces a 25 MB limit per recording and does not promise subscription-covered transcription. Provider quotas and charges are separate from OpenClaw summaries.

Not yet ported: Apple Speech local/live transcription, automatic voiceprint identification and merging, overlay window, Feishu delivery and the complete bilingual UI. UI is currently Chinese; summary output supports Chinese/English. The macOS native application remains unchanged. Meeting data is local to this Windows client; no automatic Mac/Windows sync or database interchange is provided.

## Build

```sh
npm ci
npm test
npm run dist
```

Run packaging on Windows. Artifacts: `release/TopMeeting-0.12.0-windows-x64-setup.exe` and a ZIP containing the unpacked client. GitHub Actions launches the packaged executable and checks its renderer/main storage bridge with synthetic data. This is not a physical microphone or Windows SmartScreen acceptance test.

Installer is per-user, requires no administrator privilege and is currently unsigned. No code-signing certificate is configured; Windows may display an unknown-publisher prompt. The release is a prerelease, not feature parity with macOS.

Data uses Electron's per-user application data directory. Plaintext meeting files and recordings remain on the device; model configuration is encrypted in `credentials.bin`. Do not include these in bug reports. Keeping a failed recording preserves recoverable chunks; re-opening the application does not silently upload recordings.

Electron/Chromium/Node and electron-builder retain their upstream licenses. The ZIP includes Electron's `LICENSE` and `LICENSES.chromium.html`; TopMeeting's Apache-2.0 license and notices are under resources.
