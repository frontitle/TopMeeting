# Desktop updates

Install version 0.15.0 once. Earlier builds require a manual upgrade.

On macOS, choose **TopMeeting → Check for Updates…**. Sparkle periodically checks the feed for the installed architecture. The user approves installation. Active meetings and pending summaries or document operations prevent a restart.

On Windows, use the setup EXE. Settings → Software update checks the official repository, offers a download and then a separate restart action. The installer uses SHA-512 from the release metadata. Portable ZIP users update manually.

## Publish a macOS update

1. Increment CFBundleVersion for each release and CFBundleShortVersionString for each user-facing version in the macOS build script. Build separately for each supported architecture.
2. Sign, notarize and staple the final app on the distribution machine. Archive with `ditto -c -k --sequesterRsrc --keepParent TopMeeting.app TopMeeting.zip`. Upload the immutable ZIP to the matching GitHub release first.
3. Sign the exact ZIP using `.build/sparkle-2.10.1/bin/sign_update --account TopMeeting-OTA TopMeeting.zip` on the signing machine. The Ed25519 key is separate from the Developer ID certificate. Its private half lives in the maintainer’s Keychain. A second signing machine must import the same key securely. Forks must use their own key and feed URLs.
4. Add an item to the matching file under `docs/updates/macos-*.xml` with sparkle:version (bundle build), sparkle:shortVersionString, sparkle:minimumSystemVersion and an enclosure containing the release ZIP URL, MIME type, length and sparkle:edSignature. Publish the feed after verifying the uploaded archive. An empty channel means no updates have been published.

See the [Sparkle publishing guide](https://sparkle-project.org/documentation/publishing/).

## Publish a Windows update

Increment the npm package version and lockfile before building. The Windows workflow generates latest.yml from the final x64 setup EXE. The release workflow attaches it to the matching draft alongside the EXE, ZIP and checksums. Publish the verified draft with the existing windows-vVERSION-preview.1 tag convention. Drafts and releases without matching update assets are ignored.
