## TopMeeting 0.14.0 for Windows x64

Download the setup EXE for a per-user installation, or extract the ZIP and run TopMeeting.exe. SHA-256 checksums are provided with the release. The installer is unsigned.

### First recording

Start Recording checks for local speech models before requesting the microphone. Download approximately 220 MB once, or choose audio-only recording. A download never starts recording automatically. Completed model files are reused on retry.

The workspace now uses consistent controls, quieter surfaces and light/dark colors. After a recording, a dismissible document suggestion explains how to create a document automatically next time.

### Reliability

Meeting saves are serialized and retain the previous valid snapshot. A failed save is reported to its caller and later attempts can retry. Corrupt libraries are preserved. Unreadable document or model credentials leave local recording available. If a voice profile is damaged, local transcription continues and preserves the profile for recovery. Model summaries again work through the desktop interface, keep earlier notes when a request fails, and deduplicate unchanged input.

### Checks

Windows CI checks a public four-speaker recording, packaged microphone capture, pause/resume and floating-window navigation, offline transcript finalization, speaker identification, summaries and Markdown export. Document API tests use synthetic credentials and simulated provider responses. Real tenant consent and distant-room microphone quality require live acceptance testing.

[Windows guide](https://github.com/frontitle/TopMeeting/blob/main/apps/windows/README.md) · [简体中文](https://github.com/frontitle/TopMeeting/blob/main/apps/windows/README.zh-CN.md)
