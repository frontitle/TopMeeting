# Architecture and platform roadmap

## Current implementation

- Native macOS host: SwiftUI/AppKit, AVAudioEngine, Apple Speech, Keychain.
- `SummaryProvider` and immutable `SummaryConnection`: the meeting flow calls a provider contract, not a specific OpenClaw endpoint. `ChatCompletionsProvider` supports OpenClaw and OpenAI-compatible streaming services. Provider credentials and cache identities are separate. Configuring a third-party API does not grant it an OpenAI subscription quota.
- `DocumentConnector`: the Feishu adapter provides authentication, document append and audio attachment operations. Per-operation receipts and uncertain writes remain in the host workflow.
- Settings → Extensions contains the installed model and document integrations. Google Docs, Notion, DingTalk and Tencent Docs creation use shared service adapters. macOS Feishu uses its own named CLI profile. Slack remains planned. Message-based extensions need `message.send`; they must not pretend to implement Feishu document/board capabilities.
- `packages/core`: browser-compatible JavaScript contracts for search, transcript deltas and evidence-checked summary patches. Tests use Node's built-in runner. This is a portability foundation; the current Swift client still owns its native meeting store and does not execute the JS core.
- `schemas/extension-manifest.schema.json`: a versioned capability declaration. No arbitrary plugin loader or untrusted-code sandbox is shipped.

## Storage and module boundaries

Both hosts route meeting saves and document receipts through one local archive. The Windows host serializes writes and uses same-directory atomic replacement. The macOS host checks for a newer snapshot under a short file lock. Each archive retains a prior valid snapshot and preserves an unreadable original during recovery. Live captions are kept in memory until finalized.

Provider API logic belongs in `packages/documents`. The macOS bridge and Windows host package that source directly. OS-specific account storage and UI stay in their host. The repository source check examines Git objects before push and in CI. Build directories, meeting files, credentials, local models and QA screenshots stay outside source history.

## Target boundaries

```text
macOS host       Windows host       Web UI + service
    |                 |                    |
    +------ versioned meeting/events ------+
                       |
       portable domain / summary state / search
                       |
       model adapters + document/message connectors
```

A meeting event carries a meeting ID, immutable paragraph ID, source revision, text, time range, speaker IDs and final/provisional state. Summary items carry stable IDs, kind (`fact`, `proposal`, `decision`, `action`, `open-question`) and source ID/revision references. Provider credentials and filesystem paths never belong in portable payloads.

## Windows and Web

Windows needs native capture (including device changes), a validated local or service ASR backend, credential vault integration and packaging/signing. Apple Speech cannot be reused there. Web capture requires explicit browser permission; service secrets must remain server-side, and cross-origin/auth limits need an actual deployment design. The Electron Windows host captures microphone PCM with an AudioWorklet and sends it to a bundled Python worker. Streaming sherpa-onnx transcription and the shared speaker engine run locally. Partial captions go to an independent listening window and final paragraphs enter the meeting store. Model weights are installed and verified on first use. No web client is available yet. A portable-core CI matrix is configured; a successful local Node check is not proof that remote Windows CI has run.

Keep the existing macOS client usable while adding hosts. Share contracts first, then migrate tested domain operations. Do not rewrite all native UI merely to claim cross-platform support.
