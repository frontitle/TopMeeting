# Product roadmap

The macOS and Windows desktop clients provide local live transcription, speaker identification, editable transcripts, model summaries and meeting document links. The next release decisions depend on real meeting tests.

- **Meeting library.** Date groups, keyword search and deletion recovery are available today. Project labels, recurring meeting groups and indexed search need validation against a large local library before a storage migration.
- **Incremental notes.** Portable code already validates changes against transcript revisions. The desktop applications currently summarize on demand and after recording. Wiring incremental updates into the actual providers requires stable source links, correction handling and measurable token savings.
- **Speech quality.** Evaluate distant voices, dialects and overlapping speech using consented, labeled recordings. Keep uncertain speakers editable. Avoid adding identities to force a target participant count.
- **Platform coverage.** Windows uses a local streaming model and a bundled voice runtime. A web client would need its own capture permissions, secret storage and deployment design.
- **Integrations.** Validate document creation and account renewal with real tenant permissions. Expand document delivery only when receipts and uncertain writes can be reconciled safely.

[Detailed Chinese planning notes](PRODUCT-ROADMAP.zh-CN.md)
