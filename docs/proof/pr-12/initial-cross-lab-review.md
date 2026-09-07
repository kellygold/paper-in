# Verdict: **Request changes** — 1 release-blocking defect (P1), 1 secondary P1

## P1 — Merging this commit auto-publishes download links to a release that doesn't exist

`.github/workflows/pages.yml:3-6` deploys `site/` to GitHub Pages on **every push to `main` touching `site/**`**, with no gate on the release existing:

```yaml
on:
  push:
    branches: [main]
    paths: ['site/**', '.github/workflows/pages.yml']
```

This commit rewrites the download and release-notes URLs to v0.4.2 in the same commit as the code change:
- `site/index.html:52` and `site/index.html:215` → `.../releases/download/v0.4.2/Paper-In-0.4.2-arm64.dmg`
- `site/index.html:220`, `site/install.html:149` → `.../releases/tag/v0.4.2`

**Failure scenario:** the moment this lands on `main`, the Pages workflow fires and paper-in.app's hero button, footer button, and both "Release notes & checksum" links point at `v0.4.2` assets. Until the v0.4.2 tag/release/DMG are published, every visitor who clicks Download gets a GitHub 404 — and the page still reads "v0.4.2 beta · Signed & notarized", so there's no signal that the build isn't out yet. This directly violates the stated constraint that site release links deploy only after the v0.4.2 DMG exists publicly. The `site/` changes need to be split out and pushed after the DMG is uploaded (or the workflow gated on the asset resolving).

Note this is *not* true of the other version bumps: `app/Info.plist:18-20`, `README.md:28`, and `docs/distribution.md:13` are inert until a release is cut, so they can ship with the code.

## P1 (secondary) — 0.4.2 ships with no release notes, but README and the site link to them

`docs/releases.md` still tops out at `## 0.4.1 beta — 7 September 2026`. `README.md:26` ("See the [release notes](docs/releases.md) for the latest changes and validation") and the site's release-notes links now advertise 0.4.2. The repo's convention is one entry per version (0.4.0, 0.4.1 both present), and 0.4.2's headline change is user-visible and behavior-altering — every new PDF gains an invisible text layer. Add the 0.4.2 entry, including the "recognition can be wrong; previously saved PDFs are unchanged" caveats already written into `README.md:122`.

## Areas checked, no blocking defect found

- **Strip boundaries / long-page coordinates** (`SearchablePDF.swift:59-91`): `stride(from:0,to:height,by:stripHeight)` with acceptance window `[start, end)` where `end = min(height, start+stripHeight)` tiles `[0,height)` exactly once — no gaps, no double-counted lines. `centre = top + (1-box.midY)*(bottom-top)` correctly converts Vision's bottom-left-origin normalized box into `CGImage.cropping`'s top-left-origin pixel space; `y = (height-bottom) + box.minY*(bottom-top)` correctly maps back to full-image bottom-left origin. The 192px overlap (0.64 in at 300 dpi) comfortably exceeds a text line, so a boundary-straddling line is fully present in the strip that claims it.
- **Image fidelity**: the long path draws `context.drawPDFPage(source)` from the original page ref rather than re-encoding a bitmap, and text uses `.invisible` drawing mode inside `saveGState`/`restoreGState`. `scaleX/scaleY` derive from the same `image(for:)` decode that produced the page, so the mapping is self-consistent.
- **Order/geometry**: `result.insert(..., at: index)` runs in ascending index order for both branches; the media box is taken from the source page unchanged; `page.rotation = original.rotation` (`SearchablePDF.swift:135`) carries rotation forward.
- **Failure/retry durability** (`DraftStore.swift:369-383`): recognition happens *before* `draft.export` is set, so a Vision or PDFKit failure throws with the draft intact and retryable; a retry with `draft.export != nil` reuses the retained `export.pdf` bytes and the recorded SHA-256, matching the claim in `docs/architecture.md`.
- **Background ownership**: export still runs on the single `DispatchQueue.global` path in `AppModel.swift:278` guarded by `exporting`; the new work adds no second owner of the store.
- **Native bridge/build linking**: `scripts/toolchain.sh` (which defines `paper_sdk`/`paper_arch`/`paper_swift`) is sourced before `scripts/project.sh` in all five consumers (`build.sh:5-6`, `test-native.sh:4-5`, `test-performance.sh`, `live-test.sh`, `live-native-test.sh`), so the new `xcrun clang` line and `paper_swift+=` have their inputs. `-framework Vision` is added at link time and `.build/text-recognition.o` is in both source groups. `test.sh:5-6` runs `./build.sh` before `test-native.sh`, so the `PaperOCR` path the new suite is handed exists.
- **Weak-OCR filing review**: `ai/ocr.m:10` matches the exact creator string written at `SearchablePDF.swift:40` and forces re-recognition from the page image for Paper In PDFs, so an embedded layer can't masquerade as trustworthy digital text.

## Verification limit

Permission to compile or run anything was denied in this session, so the above is a static read only. Two runtime PDFKit behaviors the design depends on were reasoned about but not executed: that `PDFPage(image:).pageRef` is non-nil and carries no `/Rotate` of its own (otherwise `drawPDFPage` at `SearchablePDF.swift:107` would rotate a second time), and that `PDFDocument.insert` of a page owned by another document doesn't re-parent it out of the source (`SearchablePDF.swift:18`, `:32` use raw pages rather than `page.copy()`). `tests/app/SearchablePDF/main.swift` asserts both — pixel-identical render plus `rotationAngle` equality on the rotated long page, and per-page distinct text across three ordinary pages — so a live `./test.sh` run should settle them. Using `page.copy() as! PDFPage` at those two insert sites would remove the dependency on undocumented behavior regardless.