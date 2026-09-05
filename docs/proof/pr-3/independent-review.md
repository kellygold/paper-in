I'll read the candidate source directly (no subagents, read-only).

Write is disabled in this session, so the review is delivered here rather than to a plan file.

## Verdict: no P0/P1 defects found

The load-bearing safety property holds. `isClearlyBlank` is behaviourally identical to 0.3.1 — every old `return false` maps to `.content` or `.possibleBlank`, every `return true` maps to `.blank` (`BlankPageDetector.swift:9,15,30,45,78,103,106`), and the new interior accumulators (`:50-52,62-67`) neither mutate `mask` nor short-circuit. Automatic skipping is unchanged.

The four scoped invariants check out:

- **PDF inclusion** — `.possibleBlank` only sets a flag (`DraftStore.swift:200-201`); `export` filters on `visiblePages` (`:58,354,357`). A suggested back always reaches the PDF until removed.
- **Durable metadata / recovery** — the flag is written into the ingest envelope before the manifest commit (`DraftStore.swift:208-214`), so the interrupted-ingest replay in `reconcile` (`:226-231`) restores it.
- **Old manifests** — `possibleBlankBack: Bool?` (`DraftStore.swift:23`) decodes as `nil` from 0.3.1 drafts; no migration needed.
- **Keep/remove/restore** — `remove` and `restore` both clear the flag (`:275-288`), so a dismissed suggestion cannot resurface, and `restoreLastRemoved` (`:296-307`) still prefers user-removed pages because a "Remove back" click leaves `blankBackSkipped == nil`. UI targeting is correct: the flag is only ever set when `expectedSides == 2 && side == 1` (`:190`), so the banner can only render in the BACK column.

## P2 concerns

**1. The interior budget is wide enough to label a legibly-written back "Possibly blank"** — `BlankPageDetector.swift:74-76`. The auto-blank gate fails on a single connected 24-pixel component (`:103`), which routes to `fallback`; `fallback` is `.possibleBlank` whenever interior strong ink is under 0.3%. For a 300-dpi A4 back (downscaled to 1131×1600, interior 1041×1472 = 1,532,352 px) that budget is ~4,597 strong pixels — roughly 1½ lines of 12-pt text. A back carrying only "Signed: J. Smith, 4 March 2026" gets "Possibly blank—check before removing" next to a **Remove back** button. No data loss (removal is reversible, page stays in the PDF), but the label asserts something false about a page with visible writing.

**2. Banner is unreachable in "Single page" layout** — `SheetPreview.swift:7,12-13`. The Keep/Remove affordance only renders under `model.pairedPreview`; in single-page mode the sole cue is the sidebar caption (`ContentView.swift:64`) with no explanation. Not blocking (the toolbar Remove at `ContentView.swift:138-142` still works), and it matches the pre-existing limitation on "Restore this side".

**3. Preview misalignment** — `SheetPreview.swift:29-36`. The banner is inserted into the back column of the `HStack` at `:8-11` only, so front and back page images sit at different vertical offsets whenever a suggestion is showing.

**4. `docs/validation.md:16`** — count raised 2 → 3, but the prose still enumerates only the two original app-flow scenarios; the new possible-blank capture scenario is undescribed. (`:12` was updated correctly.)

**5. `docs/releases.md`** — 0.3.2 is dated 5 September 2026, the same day as 0.3.1, while today is 6 September 2026. `docs/validation.md:3` still reads "verified on 5 September 2026" despite three added scenarios.

## Coverage limits

- Static reading only. Nothing was compiled or executed, so the new fixture outcomes (`creased`, `showThrough`, `dense`, and the AppFlow crease bitmap) are reasoned about arithmetically, not observed. I traced each: they should land as asserted, including the non-obvious detail that `AutoCrop.detect` returns `nil` on white-bordered fixtures (`AutoCrop.swift:73`, `background.max()! <= 235`), so the store path assesses the same uncropped image as the direct `assess` assertions.
- No SwiftUI rendering, so banner layout and `disabled(!model.canEdit)` propagation are inferred from structure.
- No hardware. The release note's claim about three locally replayed private scanner backs is unverifiable here by design.
- Out of scope and not re-examined: the pre-existing behaviour where `ingest` assesses the auto-cropped image even when `autoCrop` is off (`DraftStore.swift:191-196`), and the prior release's blank thresholds.
