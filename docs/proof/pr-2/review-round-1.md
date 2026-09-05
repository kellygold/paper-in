## Verdict

The feature is soundly built and I found **no P0 and no data-loss defect**. Originals, `sheetID`/`side`/`expectedSides`, capture counts and envelope recovery all behave as documented; old manifests decode cleanly (`blankBackSkipped` is `Bool?`, so a missing key is `nil` and legacy pages are never reclassified). One P1 restore-targeting defect, plus two supported P2s.

### What I re-derived and confirmed correct

- **Fronts are never skipped.** `DraftStore.swift:189` requires `expectedSides == 2 && side == 1`, and `ESCLScannerBackend.swift:170` runs exactly one capture per sheet delivering 1–2 images, so ordinal 1 is always the back of that sheet. Failure paths (image fetch or manifest commit failing on the front) leave `capture.received` at 0, so the next image becomes side 0 — the safe direction.
- **Capture count includes skipped sides** (`DraftStore.swift:207` adds `pages.count` regardless of `removed`), so `onCaptureEnded(success: received > 0)` is unaffected.
- **Restart/interrupt recovery** replays the ingest envelope written at `DraftStore.swift:203` *before* the manifest commit, carrying `removed`/`blankBackSkipped` through `reconcile()`.
- **Paired preview stays consistent**: `AppModel.swift:117` builds `sheetPreviews` only from `visible` siblings, and `refresh(selectLast:)` selects the front (last *visible*) page after a skipped back.
- **Detector conservatism holds.** Skipping requires: background ≥225 on all channels with ≤12 spread, <30 strong and <200 total marked pixels, and every connected component <24 px and <5 strong px (`BlankPageDetector.swift:40`, `:58`, `:83`). Solid ink survives the ~0.48 downscale of a 300 dpi letter page via the `strong >= 5` rule.

### P1

**Wrong page restored by the only discoverable restore control.**
`app/documents/DraftStore.swift:291` — `restoreLastRemoved()` picks `pages.lastIndex(where: { $0.removed })`, i.e. last in *document order*, not last removed. `app/ui/ContentView.swift:77` is the sole global restore affordance.

Scenario: duplex sheet scanned with skipping on → `pages = [front, back(removed, blankBackSkipped)]`. The user removes the front (`ContentView.swift:137`). The sheet now has no visible page, so `SheetGroup.make` drops it (`SheetGroup.swift:20`), `sheets` is empty, `selectedSheet` is nil, and the per-side "Restore this side" button at `SheetPreview.swift:39` becomes unreachable. The only remaining control is "Restore removed page", which restores index 1 — the auto-skipped **blank back**, not the front the user just removed. `blankBackSkipped` is cleared (`DraftStore.swift:293`), so the sidebar then reads "Front + back" while the document contains only the blank side; Save PDF exports a one-page PDF of blank paper.

Not data loss (the front is still recoverable with a second click, and the preview shows the state), but the undo affordance acts on a page the user never removed and can put an unwanted blank page in the export. The `lastIndex` ordering flaw exists at base `ccfe416`; the change makes it reachable after a *single* user removal because the app now creates `removed` pages on its own — and `restoreLastRemoved` is touched by this diff without addressing it.

### P2 (tightly supported)

1. **Detector runs synchronously on the main actor.** `ESCLScannerBackend.swift:176` calls `onImage` inside `Task { @MainActor }` → `AppModel.swift:86` → `DraftStore.ingest`. For each back this now adds a full-page CGContext render, a 3×256 histogram over ~2M pixels and a connected-component pass (`BlankPageDetector.swift:27–85`), **plus a newly-added `AutoCrop.detect` run even when auto-crop is off** (`DraftStore.swift:190–192` — the `autoCrop || (skipBlankBacks && isBack)` condition computes `crop` unconditionally). The UI is blocked and the eSCL job stays open for that duration. Bounded and per-back only, but it is new main-thread work on the capture path.

2. **Test fixtures exercise the detector at a scale production never uses.** `tests/app/BlankPages/main.swift` fixtures are 1000×1400, so `scale = min(1, 1600/1400) = 1` and no downscale occurs; a real 300 dpi letter scan is 2550×3300 → scale ≈ 0.48, i.e. ~4× smaller in area. The 24-pixel component and 200-pixel totals therefore correspond to ~4× larger physical marks in production than in the retention fixtures (`ink` 4×9 px, `edge` 2×30 px). The dark-ink cases still survive at production scale via `strong >= 5`, but the **faint** band (contrast 7–21, which relies solely on the 24-pixel component rule) is untested at the real working scale — a faint pencil smudge under roughly 0.15″ would be classified blank. This is a coverage gap, not a demonstrated misclassification; I'm not claiming the thresholds are wrong.

### Coverage limits

Read-only, single pass with one double-check of the two concrete findings. I did not build, run the test suite, or touch hardware, so nothing here is an empirical result — the detector's real-world false-positive rate on actual DS-940DW backs is unassessed, and I did not verify that the new test files compile or that `scripts/test-native.sh:23` links correctly. I reviewed changed production code (`BlankPageDetector`, `DraftStore`, `AppModel`, `ContentView`, `SheetPreview`) in full and read `AutoCrop`, `SheetGroup` and the eSCL capture loop only far enough to check the side-ordinal and crop-then-detect contracts; filing, discovery and transport were not reviewed.