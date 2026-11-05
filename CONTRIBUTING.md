# Contributing

TopMeeting is an Apache-2.0 project. Keep platform-specific capture, credentials and UI separate from meeting data and connector contracts.

## Before publishing source

Enable the repository hook with `git config core.hooksPath .githooks` in a fresh clone. Run `python3 scripts/check-source.py --index` before committing and `python3 scripts/check-source.py --history HEAD` before publishing. The checks inspect Git objects and report paths only. The hook checks the history being pushed, including files added and removed in earlier commits.

## Local checks

- macOS with Swift 6 and macOS 26+ SDK: `swift build -c release` and `./scripts/check.sh`.
- Node.js 22+: `node --test packages/core/test/core.test.js packages/documents/test/*.test.cjs` (no network or dependencies).
- UI strings: edit `localization/en.tsv`, then `python3 scripts/generate-localization.py`.
- Native previews: `./scripts/preview-workspace.sh /absolute/path/preview.png`; use `dark`, `compact` or `picker` to inspect specific states. Fixtures never load the user's real meeting store.
- Real audio checks require your own authorized sample: `./scripts/check-continuous-speech.sh /absolute/path/sample.wav`. Do not commit the audio or recognized text.

For a change, explain the user-visible behavior, affected platforms, validation and limits. Add regression checks for state, persistence, provider requests and data-loss risks. Avoid tests that merely duplicate styling code.

## Contribution boundaries

Never commit tokens, meeting content, voiceprints, diagnostic dumps or home-directory paths. Do not use live providers in CI or spend a contributor's API quota during tests. Do not publish cloud documents from tests. A connector must handle uncertain writes without blindly retrying non-idempotent operations.

Keep third-party notices. Do not copy code from a repository without verifying the applicable license. Contributions are submitted under Apache-2.0; do not change project licensing in an unrelated patch.
