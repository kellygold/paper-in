# Independent searchable PDF validation

Candidate: `3fcbdb6a66aecb81323d78bffc514c10767b1bb5` (clean before and after). Base supplied: `45af1f1c271126ddeff7a1e86f28907b9565d940`.
Worktree: `/Users/kgold/Code/paper-in/.build/validate-searchable`.

## Results

- Candidate synthetic SearchablePDF test compiled independently and passed. A probe copy retained its synthetic baseline/export PDFs; candidate source was not changed.
- Poppler `pdftotext -layout` found no baseline text and extracted all receipt invoice/amount fragments exactly once per page from the export. This is persisted PDF text, independent of Preview Live Text/OCR.
- 945 × 18000 px / 300 dpi long receipts (~1.52 m): start 12345, tile-boundary items 55555/66666, middle 67890, ending amount 246.80 all extracted once on both upright and rotated pages. Ordinary receipt invoice 82746 / amount 139.00 extracted upright and rotated. Blank page had no text.
- Five 72 dpi Poppler rendered PNGs matched baseline byte-for-byte; all five full-resolution embedded images extracted by `pdfimages -png` also matched byte-for-byte. Embedded receipt dimensions remained 1200 × 2000 and long images 945 × 18000 at 300 dpi. CoreGraphics checks also passed visible pixel, media box and rotation equality.
- Separate gray-rim fixture variant enabled actual auto-cropping. Ordinary receipt image changed to 1140 × 1940 before export and preserved that size plus searchable amounts through export and rotation. Long-page gray rim exercised background handling but retained full dimensions; no claim of physical long-page cropping.
- Inspected synthetic-receipt.png visually: clean upright receipt, invoice and total readable, no visible text overlay artifacts.
- No concrete defect found within this lane. This is evidence, not a release verdict.

## Commands

From the worktree, for each ignored probe (`.build/independent-probe/main.swift` and `.build/independent-crop-probe/main.swift`):

```sh
source scripts/toolchain.sh
source scripts/project.sh
xcrun swiftc "${paper_swift[@]}" "${paper_documents[@]}" .build/independent-probe/main.swift -o .build/independent-probe/run
.build/independent-probe/run
```

Probe 1 differs from `tests/app/SearchablePDF/main.swift` only in ignored output location, retaining synthetic data, and writing baseline/export copies. Probe 2 additionally draws a 30-pixel gray rim and enables `ingest(..., autoCrop: true)`, requiring a detected crop on the ordinary receipt.
Exact Poppler command argument lists and hashes are recorded in `external-reader.json`.

## Boundaries and cleanup

Synthetic fixtures only; no real receipts, scanner operation, application launch/rebuild, provider request, account access, GitHub change or publishing. No AI helper argument was passed: this lane does not independently validate filing confidence. No language, handwriting or degraded real-scan accuracy generalization. No latency/release verdict; root coordinates other lanes.
Temporary synthetic draft roots and duplicate extracted images/rasters removed after checks. Retained: two synthetic exported PDFs, one screenshot, extracted text, image inventory, logs and JSON/Markdown evidence. Ignored probe source/binaries remain in disposable validation worktree for root cleanup. Shared `.build/Paper In.app` untouched.
