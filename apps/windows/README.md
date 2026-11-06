# TopMeeting for Windows

[简体中文](README.zh-CN.md) · [Installer, ZIP and SHA-256 checksums](https://github.com/frontitle/TopMeeting/releases/tag/windows-v0.15.0-preview.1)

## Your first meeting

1. Create a meeting and click **开始录音** (Start recording).
2. If models are missing, choose **下载模型** to download approximately 220 MB for local captions and speaker matching. Choose **先只录音** to record audio without a transcript. The microphone stays closed during setup.
3. Once the models are ready, click Start. Partial captions appear in the listening window. Completed paragraphs appear in the transcript.
4. Click the speaker count to name people or merge duplicate identities. Double-click the floating caption area to return to the main window.
5. End recording to save audio and text. A configured model can generate notes. Open Settings to bind a document account for future meetings.

Verified model files are reused after a failed download. Transcription and voice identification run offline after installation. The document suggestion appears after a recording and can be dismissed.

## Document accounts

| Service | Setup |
|---|---|
| Feishu | Register your own Feishu app, enable user document permissions and configure the callback `http://127.0.0.1:39427/callback`. Complete authorization in the system browser. |
| Google Docs | Enable the Docs API and configure a desktop OAuth client. Select the Google account used to create meeting documents. |
| Notion | Provide an internal integration token and the ID of a parent page shared with that integration. |
| DingTalk | Supply the organization's AppKey and secret, knowledge space, operator Union ID and an optional parent node. The app needs write permission there. |
| Tencent Docs | Obtain a personal MCP token from [Tencent Docs](https://docs.qq.com/open/auth/mcp.html). Binding checks the available document-creation tool. |

Select one workspace and save it as the automatic destination. Switching the destination keeps previously bound accounts and existing meeting links. Open the returned link from the meeting. If a request is interrupted, check the provider before retrying. The Windows client handles document creation and links. Full transcript, attachment and board delivery is available through the macOS Feishu adapter.

## Development

Use Windows x64, Node.js 22+, Python 3.13 and Chrome for browser tests. From this directory:

```powershell
npm ci
npm test
node test/ui-journey.cjs
./speech/build-runtime.ps1
npm run dist
```

Outputs are written to `release/`. Windows CI replays a public four-speaker Mandarin recording through the packaged app using a fixture microphone, exercises the floating panel, and checks audio-only capture, storage, summaries, failure recovery and export. Real tenant consent and physical microphone quality require a separate live acceptance test.

Meeting metadata, recordings and voice profiles live in Electron's per-user application data directory. Credentials use Windows safeStorage (DPAPI). Releases are currently unsigned. See [Security](../../SECURITY.md) and [third-party notices](../../THIRD_PARTY_NOTICES.md).
