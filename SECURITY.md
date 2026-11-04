# Security and privacy

Meeting audio, text, speaker profiles and access tokens can be sensitive. Raw recording and speaker inference run locally. Only explicit assistant/summary requests send meeting text to the configured model provider. Enabling Feishu sync sends the selected meeting content and, when enabled, audio attachments to that account.

Tokens are stored in macOS Keychain under separate provider accounts. Never include them in exports, logs, issues or screenshots. Other platforms must use their OS credential store or a server-side secret vault; browser bundles/localStorage must not contain service credentials.

Do not disclose vulnerabilities together with user meeting data in public issues. Use the repository's private vulnerability reporting channel when enabled, or privately contact the maintainer through their published profile. A public support mailbox has not yet been configured.

The current macOS app is a development build, not a notarized production distribution. Extension interfaces are compiled-in adapters, not a sandbox for untrusted downloaded code. Public release must review model redistribution rights, signatures, dependency notices and data migrations.
