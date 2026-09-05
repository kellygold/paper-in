# Paper In

A small native Mac scanner app: **scan, add more sheets, save one PDF**.

Version 0.2.0 adds paired front/back previews and optional AI filing. The supported scanner is **Brother DS-940DW over USB on macOS**. This is a community project, not a Brother product.

## Use

1. Close other scanner applications, power on the DS-940DW in USB mode and click **Connect**.
2. Insert a sheet and press **Scan** or Space. Keep adding sheets to the document.
3. Review **Front + back** together, or switch to **Single page**. Select either side to rotate, crop or remove it. Zoom each preview independently. Removed sides can be restored.
4. Press **Save PDF** or Command-S. The destination is remembered, and a fresh document starts.

Every completed image is committed to a recoverable draft. Originals and reversible crop metadata are retained. Older drafts remain readable; pages without trustworthy sheet metadata stay individually displayed instead of guessing pairs.

## Optional AI filing

Choose your document root with **Change…**, then open **AI filing…**. It is off by default. New documents are first saved under `_Inbox` in that root. A separate worker performs local OCR, proposes a name and folder, checks relevant existing documents, and cross-checks its proposal with a second model call. Scanning remains available while it works.

- **Codex:** official Codex SDK with its runtime's existing login (`codex login`).
- **Claude:** official Claude Agent SDK with its runtime's existing login (`claude auth login`). Paper In identifies itself as `paper-in/0.2.0`; it does not extract tokens or impersonate another client. Provider eligibility, subscription limits and terms still apply. See [provider notes](docs/providers.md).
- **API keys:** OpenAI Responses or Anthropic Messages. Enter a model identifier and store the key in macOS Keychain. API billing is separate from subscriptions.

Node.js **22+** is needed for AI filing. Scanning works without Node. Runtime paths are auto-detected and can be overridden in settings. The source build installs pinned SDK dependencies locally; it never changes your global CLI installations.

Automatically filing clear matches is optional. New folders, weak OCR, low confidence, disagreement between checks, duplicates and possible continuation pages require review. Open **Saved documents** to change the proposed name/location, approve filing, retry a failed job, reveal the PDF or Undo. Retry uses the currently selected provider settings. Names are never allowed to escape the selected root. Existing files are not overwritten; a short ID resolves ordinary name collisions. Related documents are never automatically merged or deleted.

The worker sees the folder structure, hashes existing PDFs for exact duplicates, and locally reads up to eight ranked candidate PDFs. It is a bounded comparison, not a claim to have semantically compared every page of a large archive. OCR and small-file indexing can take time on first use. Existing PDFs are read for context; only newly saved, explicitly opted-in exports become filing jobs.

### Privacy and recovery

When AI filing is enabled, extracted text, folder names and candidate excerpts are sent to the selected provider. Original page images are not uploaded by this implementation. OCR is local. The worker uses a separate empty working directory for each job; agent execution tools and external integrations are disabled. Providers can retain data according to the selected account and runtime settings. Codex can retain its own local session history.

Drafts, original PDFs, the queue and local OCR cache live under `~/Library/Application Support/Paper In`. API keys are stored in Keychain and passed only to the worker's stdin. Diagnostics omit document text and provider response bodies. Nothing is written into a notes vault or sent through a project server.

Published-export manifests are the durable handoff: if the app quits between saving and starting AI, the next run discovers that job. Interrupted analysis is retried. Publishing and Undo have persisted intent records and retain original bytes. Changed files are not deleted by Undo. Source scans and old drafts are retained; there is no automatic storage cleanup yet.

## Build and test

Requirements: macOS 14+, Xcode or Command Line Tools, Node.js 22+ and npm for the AI worker dependencies. Apple Silicon is tested; other Mac architectures are not yet validated.

```sh
./build.sh
open '.build/Paper In.app'
./test.sh
```

The build uses the selected SDK and host architecture, with a narrowly scoped fallback for the known Swift 6.1.2 / mismatched CLT installation. `PAPER_IN_SDK` and `PAPER_IN_ARCH` can override these choices. No system settings are changed. Builds are ad-hoc signed for local use; public downloadable releases need signing/notarization work.

For scanner-free UI inspection:

```sh
open -n '.build/Paper In.app' --args --demo
open -n '.build/Paper In.app' --args --demo --demo-settings
open -n '.build/Paper In.app' --args --demo --demo-review
```

Demo mode uses generated pages and temporary storage and refuses provider requests. `--screenshot /absolute/path.png` exports the demo window for visual review.

`./test.sh` runs native persistence/PDF/crop/scanner-contract tests and Node queue/provider tests. Live synthetic provider checks are separately opt-in; see [validation](docs/validation.md).

## Extend

The app has one shared document workflow, a `ScannerBackend` contract and a shared AI proposal contract. Supported implementations are registered in catalogs. Start with [architecture](docs/architecture.md), which includes adding a provider or scanner and the tests an implementation must pass.

## Current limits

- Only the DS-940DW USB profile is supported and hardware-tested. Network scanners, other Brother models, flatbeds and multi-sheet ADFs are not advertised as supported.
- Capture remains A4, 300 dpi, colour. Automatic crop sizes small items correctly; it does not extend acquisition for long receipts or deskew pages.
- Physical scanner-button events and automatic insertion scanning are not implemented. Use Scan or Space.
- Local OCR feeds classification; exported PDFs do not yet receive a searchable text layer.
- Image processing and PDF generation remain on the main thread; very large documents may briefly pause export. AI work runs outside that thread.
- AI output is fallible. Both checks use the selected provider, and confidence is not a measured probability. Review and Undo remain available.

Paper In source is MIT licensed. Bundled/development dependencies retain their own licenses, including the proprietary Claude Agent SDK/runtime. See [third-party notices](docs/third-party.md).
