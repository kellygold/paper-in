# Independent delta validation: overlap handling

Candidate `809b483abd5c0e62866a2ffe326fc6ee6f84407b`, clean exact head before and after. This supersedes runtime evidence for the overlap algorithm from `3fcbdb6`; the prior receipt remains preserved.

Reran the same retained synthetic probe against the candidate source. The production delta retains observations from overlapping strips and coalesces overlapping boxes instead of assigning ownership by recognition centre. No additional broad sweep or crop rerun.

Results: candidate probe passed all persisted text, visible CoreGraphics raster equality, geometry/rotation and source-byte assertions. Independent Poppler 26.03.0 `pdftotext -layout` found an empty image-only baseline, receipt invoice 82746 and amount 139.00, plus long receipt start 12345, boundary items **55555 and 66666**, middle 67890 and final amount 246.80 **exactly once on each relevant upright and rotated page**. Blank page remained empty. `pdfimages -png` extracted five full-resolution images with byte-identical hashes before and after OCR; receipt and 1.52 m long-page image resolution retained.

Commands run from `.build/validate-searchable`:

```sh
source scripts/toolchain.sh
source scripts/project.sh
xcrun swiftc "${paper_swift[@]}" "${paper_documents[@]}" .build/independent-probe/main.swift -o .build/independent-probe/run
.build/independent-probe/run
```

Exact external command arrays, per-page counts and hashes: `delta-809b483.json`. Retained output: `synthetic-searchable-809b483.pdf`, `delta-809b483-extracted.txt`, image inventory and probe log.

Limit: **local macOS 26.3.1 evidence only; this does not establish macOS 15 behavior**. Root must verify macOS 15 CI independently. No release verdict or concrete local defect.

Cleanup: synthetic temporary draft and duplicate extracted images removed. Candidate source unchanged, previous evidence preserved. No personal scans, scanner activity, installed app rebuild/restart, provider/account access, GitHub mutations, or new agents. Ignored probe source and executable remain in disposable validation worktree for coordinator cleanup.
