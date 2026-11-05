# Security and privacy

Meeting audio, text, speaker profiles and access tokens can be sensitive. Raw recording and speaker inference run locally. Assistant requests and end-of-meeting summaries send meeting text to the configured model provider. Windows live transcription runs locally after the one-time model installation. Enabling Feishu sync sends the selected meeting content and, when enabled, audio attachments to that account.

Enabling automatic document creation sends the title at recording start to each selected document service. Document links are saved only after a provider receipt.

Model and document credentials use macOS Keychain or Windows safeStorage (DPAPI), with Feishu CLI credentials in its dedicated Mac profile. Never include them in exports, logs, issues or screenshots. Other platforms must use their OS credential store or a server-side secret vault; browser bundles/localStorage must not contain service credentials.

Do not disclose vulnerabilities together with user meeting data in public issues. Use the repository's private vulnerability reporting channel when enabled, or privately contact the maintainer through their published profile. A public support mailbox has not yet been configured.

The current macOS app is a development build, not a notarized production distribution. Extension interfaces are compiled-in adapters, not a sandbox for untrusted downloaded code. Public release must review model redistribution rights, signatures, dependency notices and data migrations.
