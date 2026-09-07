# User-authorized additional review

Candidate fcf7b1898f4c3642c5f088dc7224b089b8c6ba67. Claude Opus high completed in 313.2 seconds. The user explicitly authorized continuing the runbook after the first timeout. No source changes from the reviewer.

## Verdict

**One release-blocking finding (P1, sequencing). No code-level P0/P1 defects found in the reviewed focus areas.**

### P1 — Site deploy publishes a download link to assets that don't exist yet

`site/index.html:52` and `site/index.html:215` now point the primary Download buttons at `.../releases/download/v0.4.1/Paper-In-0.4.1-arm64.dmg`; `site/install.html:81` and `site/install.html:149` advertise 0.4.1 and link its release tag.

Failure scenario (checked once): `.github/workflows/pages.yml:4-6` triggers on `push` to `main` filtered on `paths: ['site/**']`, and deploys the `site/` directory to GitHub Pages. Merging this candidate to `main` therefore publishes the 0.4.1 links immediately. The repo's own gate state says the asset isn't there yet — `docs/validation.md:3`: "Version 0.4.0 remains the published signed installer until those release gates pass," with signing/notarization tracked in PR #10. Result: every visitor's Download button 404s until the v0.4.1 release with the notarized DMG is created.

Fix is ordering, not code: publish the v0.4.1 tag + DMG first, then land/deploy the `site/**` change (or land the merge with `site/**` reverted and deploy it after the release).

### Focus areas checked — no blocking defects

- **Background export / exclusive `DraftStore` ownership.** Every main-thread path into `store` during export is gated: `refresh` (`app/ui/AppModel.swift:144`), `select` (`:160`), `canEdit` → `edit`/`startOver`/`moveSelectedPage`/`scan` (`:64`), and `scanner.onBegin` (`:101`). `onPage`/`onEnd` lack an explicit `exporting` check but are unreachable during export: `save()` requires `!scanner.busy` (`:270`), capture only starts via `ESCLScannerBackend.scan` which sets `busy = true` synchronously before the capture Task (`app/scanning/ESCLScannerBackend.swift:141`), and `onCaptureEnded` fires with no suspension point after `busy = false` (`:204-205`). Views only read `model.store == nil`. Snapshot of `destination`/`settings` is taken before dispatch (`AppModel.swift:275-277`).
- **Preview snapshots/cancellation.** `PreviewRenderer` returns immutable `CGImage`s; `AppModel.select` cancels the prior task before dispatch, and `save()` cancels it too (`:273`). After cancellation the task can only reach `Task.checkCancellation()` at `PreviewRenderer.swift:70`/`AppModel.swift:184` before any `self.store` access at `:185`, so no store read races the background export. Cache is keyed on folder+source+frame+rotation+crop+pixels and bounded (64 MiB / 80 entries).
- **Discard/restart integrity.** `discardDraft` (`app/documents/DraftStore.swift:115`) requires `export == nil` and no live capture, then `newDraft()` writes the new manifest before flipping `current.json` (`:99-100`). A crash on either side of the pointer write leaves an intact old or new draft; no source bytes are deleted. A discarded draft has no published export, so `discover()` skips it (`ai/engine.mjs:72`).
- **Dismissal vs. durable discovery.** `discover()` skips any draft whose `job.json` exists (`ai/engine.mjs:65`), so dismissed entries are not recreated; `run()` never selects `dismissed` (`:313-317`). All commands, including `dismiss`/`dismissAll`/`restoreEntry`, run under `withLock` (`ai/main.mjs:15-23`), and the UI disables them while `filing.busy`, so no state overwrite race with an in-flight analyze.
- **Deleted/moved originals.** `analyze` fails closed to `missing` (`:100`) and `publish` re-checks before filing (`:182`); `FilingController.refresh` computes `fileMissing` from target-for-filed / original otherwise (`app/filing/FilingController.swift:94`), and the UI hides Apply/Undo/Retry while missing but keeps "Show retained original". Secrets restricted to `command == "run"` is safe: `retry` re-triggers `run()` afterward (`FilingController.swift:229-231`), and no other command calls a provider.
- **`same_vendor` exemption.** `reviewReasons` (`ai/review-policy.mjs:9-10`) preserves every prior gate, considers both passes' relations, and treats any non-`same_vendor` value — including off-enum strings, which `validateProposal` does not constrain — as review-worthy. Byte-identical duplicates still force review via `context.duplicate` regardless of the model's label. Worst case of a mislabeled near-duplicate under autoFile is a second file under a suffixed name; nothing is overwritten or deleted and the snapshot is retained.

### Non-blocking notes

- `DraftStore.discardDraft`'s `draft.capture == nil` guard uses persisted state that is only cleared by `completeCapture`. After a force-quit mid-scan, "Start over…" reports "Stop scanning before starting over." until the next scan completes. No data loss; per-page removal still works.
- `select()` clears `preview`/`sheetPreviews` synchronously on every `refresh()`, so a cache-hit re-selection still shows one frame of "Loading preview…".

## Coordinator triage

The Pages deployment sequencing concern is confirmed by the workflow and is an existing explicit release gate: publish and verify v0.4.1 assets before merge. It requires no code change and remains open until that ordering has been completed. No blocking code defects were reported. The persisted-capture limitation is confirmed by DraftStore.reconcile/discardDraft: starting over after force-quit during capture may require another capture to finish. It is non-blocking, does not delete data, and is retained here for follow-up. The cache-hit loading-frame note matches select() behavior and is non-blocking. Tests and performance measurements remain applicable; no code delta.
