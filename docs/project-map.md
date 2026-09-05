# Project map

Start here if you want to understand or change Paper In.

## The two parts

**`app/` is the Mac app.** It talks to the scanner, shows pages, keeps the draft safe, and saves the PDF. Its AI settings screen launches a separate process after Save.

**`ai/` is that filing process.** It reads the saved PDF, calls the selected provider, checks its suggestion, and manages filing and Undo. It never owns the scanner connection.

```text
Paper → Scanner → Draft → Save PDF → AI suggestion → Review or file
        app/      app/     app/       ai/             app/ + ai/
```

## What to open

| I want to… | Start here |
| --- | --- |
| See how the app starts | [app/App.swift](../app/App.swift) |
| Change the main window or controls | [app/ui/ContentView.swift](../app/ui/ContentView.swift) |
| Change what Scan or Save does | [app/ui/AppModel.swift](../app/ui/AppModel.swift) |
| Change the paired preview or zoom | [app/ui/SheetPreview.swift](../app/ui/SheetPreview.swift), [PagePreview.swift](../app/ui/PagePreview.swift) |
| Understand draft recovery or PDF creation | [app/documents/DraftStore.swift](../app/documents/DraftStore.swift) |
| Change page pairing or cropping | [app/documents/SheetGroup.swift](../app/documents/SheetGroup.swift), [AutoCrop.swift](../app/documents/AutoCrop.swift) |
| Add a scanner | [app/scanning/ScannerBackend.swift](../app/scanning/ScannerBackend.swift), then [ScannerCatalog.swift](../app/scanning/ScannerCatalog.swift) |
| Debug the Brother connection | [app/scanning/DS940USBBackend.swift](../app/scanning/DS940USBBackend.swift) |
| Change AI settings or the review screen | [app/filing/FilingViews.swift](../app/filing/FilingViews.swift) |
| Understand how Swift starts the AI process | [app/filing/FilingController.swift](../app/filing/FilingController.swift) |
| Change the naming instructions or AI response format | [ai/schema.mjs](../ai/schema.mjs) |
| Change when documents need review | [ai/engine.mjs](../ai/engine.mjs) |
| Add an AI provider | [ai/providers/registry.mjs](../ai/providers/registry.mjs), then [provider-catalog.json](../ai/provider-catalog.json) |
| Change how related documents are found | [ai/library.mjs](../ai/library.mjs) |
| Understand file safety and Undo | [ai/engine.mjs](../ai/engine.mjs), [files.mjs](../ai/files.mjs) |
| Change local OCR | [ai/ocr.m](../ai/ocr.m) |
| Run tests or debug the build | [development.md](development.md) |

## Inside each folder

- **app/ui:** window layout, scan/save actions, page previews.
- **app/scanning:** one shared scanner interface, a catalog of supported backends, the current Brother implementation, and reusable eSCL transport.
- **app/documents:** saved pages, sheet identity, reversible edits, cropping, PDF export.
- **app/filing:** native settings/review UI, Keychain access, and the bridge to the AI process.
- **app/support:** diagnostic logging and the shared app error type.
- **ai/providers:** provider-specific authentication and request formats. The filing engine calls every adapter through the same interface.
- **tests/app:** native document, crop, connection, scanner contract, and app-flow tests.
- **tests/ai:** filing transactions and provider request/response tests. The `live` and `end-to-end` scripts are opt-in.
- **scripts:** shared compiler settings and test/build helpers. The root `build.sh` and `test.sh` are the normal entry points.

The small `docs/history/` folder preserves the original prototype plan. It is historical context, not the current implementation guide.

## What is deliberately shared

New scanners reuse the session, previews, draft store, and export workflow. New providers reuse OCR, prompts, proposal validation, review policy, file publication, and Undo. Model IDs are configuration, not new modules.

There is no dynamic plug-in loader or separate framework package for each feature. At this size, folders and explicit interfaces keep the code easier to follow. Split packages only when there is a real second consumer or a build boundary worth enforcing.

For the precise contracts and extension steps, continue to [architecture](architecture.md).
