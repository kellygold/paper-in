# Paper In

A personal Mac scanning prototype for the Brother DS-940DW.

**Scan → scan more pages → Save PDF.** Every completed page is committed to a recoverable draft before the app labels it saved. Save PDF combines the current pages into one file in `~/Documents/Scanned Documents` and opens a fresh draft. The destination is remembered if changed.

## Current state

Version 0.1.4 enables automatic cropping by default. It detects the item against the scanner’s neutral roller background and padded area, preserves a small border, and sizes each PDF page from the cropped pixels at the original DPI. It stores reversible crop metadata; original image bytes are unchanged. The preview, thumbnails and exported PDF use the same crop. Full scan restores the original view of any page. Ambiguous backgrounds retain the full image. Existing pages in the current draft are processed once on upgrade, with removed-page states preserved; pending exports are not changed.

Real single-sided and duplex capture through the app are confirmed. Kelly confirmed both sides, and the direct USB logs recorded two saved images. The crop was checked on those real front/back images and on an exported two-page PDF: both pages are now approximately card-sized. Automated checks cover card/receipt bounds, full white pages, the scanner's two different background tones, per-page PDF dimensions, original preservation and crop restoration across restart.

Capture still uses the proven A4 / 300 dpi colour request. Automatic cropping handles smaller items; it does not extend the acquisition area for receipts longer than A4. Very dark, coloured or ambiguous backgrounds can require using Full scan. Cropping does not deskew the original. Physical scanner button control remains unimplemented; use Scan or Space.

Implemented:

- One current document with no artificial page-count limit.
- Scan / Space to append; Save PDF / Command-S to finish.
- Persistent drafts, including recovery after a interrupted capture or failed manifest commit.
- Page thumbnails, preview, rotation, earlier/later controls and reversible removal.
- A4 acquisition at 300 dpi in colour; both sides and automatic cropping are remembered. Each PDF page uses its own resulting size.
- Remembered output folder, collision-safe PDF publication and retryable pending exports.
- Menu bar controls; closing the window leaves the app available.
- Explicit Connect / Pause. Discovery and sessions do not start merely by launching the app.
- Local connection timeline, scanner status, HTTP acceptance/rejections, page reception and save events.
- No firmware changes, reset commands, background status poller, document uploads or AI requests.

Hardware-dependent work remaining:

- Single-sided and duplex capture are confirmed; continue checking orientation with other document types.
- Physical scanner Start-button delivery is not implemented in the direct USB backend; use Scan or Space.
- Validate actual unplug/replug and sleep/wake behavior and diagnostic error handling.
- Long receipts and dedicated card presets are not enabled in this first prototype. Use ordinary A4 paper for initial testing.
- A scan that stops before a complete image arrives may need to be repeated. The app cannot reconstruct a page the scanner never delivered.

## Run

```sh
./build.sh
open '.build/Paper In.app'
```

The first launch starts paused. Close other scanning apps, load an ordinary sheet, then click Connect. Once Ready, use Scan or Space for the first capture. The scanner's Start button is a separate hardware test.

For previewing without any scanner access:

```sh
open -n '.build/Paper In.app' --args --demo
```

Preview mode uses generated sample pages and a separate temporary draft/output folder. It cannot connect to the scanner. Scan next page adds another sample; Save PDF writes a sample PDF into that temporary output folder.

The build uses an existing macOS 15.5 SDK with this Mac's Swift 6.1.2 compiler. A project-local VFS overlay hides a duplicate SwiftBridging module map during compilation. System files and the selected developer directory are not changed. The produced app targets Apple Silicon, macOS 14+, and is signed locally with an ad-hoc signature.

## Verify

```sh
./test.sh
```

Tests exercise original-byte preservation, append after restart, two-frame image order, interrupted capture, recovery after a page arrives but the manifest write fails, reversible edits, retry after PDF publication is interrupted, output failures, collision refusal, an organizer moving finished PDFs, invalid input, a 40-page PDF and image orientation metadata. They do not prove hardware compatibility.

## Storage and diagnostics

Drafts and original image files: `~/Library/Application Support/Paper In/drafts/`.

The active draft is referenced by `current.json`. Old drafts are retained after successful export; there is no automatic cleanup in this prototype. Raw transfer files are also retained for now. Only completed PDFs are published into the output folder, so the document organizer does not inspect a draft while it is being assembled.

Connection logs: `~/Library/Application Support/Paper In/Diagnostics/`. Use **Show connection log** in the menu bar. Each launch creates a local JSONL timeline. Entries include session opening, feeder capabilities, scan requests, incoming page files, durable saves, completion and framework errors. The direct backend records acceptance only after HTTP 201 and page saving only after an image has been received and committed. Logs do not contain page images or extracted document text. Framework error descriptions can include local paths; review before sharing.

If output publication fails, the app retains the draft and pending export for retry instead of allowing new pages to silently alter that export. If a different file occupies the chosen generated filename, nothing is overwritten; move that conflicting file away before retrying. The UI currently keeps the destination fixed while an export is pending.

Stop lets the current in-flight transfer finish and preserves its completed image before closing the owned job. No scan request is automatically retried.

Known limits: image decoding/draft commits and PDF work currently run on the main thread; extremely large documents may briefly pause the UI during export. A pathological crash immediately after publication combined with another process moving that PDF before publication is recorded can cause a duplicate on retry; original pages remain preserved. Neither condition has been presented as a solved hardware or full production reliability guarantee.

Latest handoff: version 0.1.4 preserves the active multi-page draft and its removed-page choices, and enables automatic cropping for new scans. The installed 0.1.3 app and the draft manifest before cropping are backed up under .build/.
