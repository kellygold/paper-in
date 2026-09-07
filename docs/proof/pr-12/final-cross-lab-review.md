## Verdict: no release-blocking defects found. Ship.

**Scope reviewed:** `809b483` vs `3fcbdb6` — `app/documents/SearchablePDF.swift`, `docs/releases.md`, `tests/app/SearchablePDF/main.swift`. Static review only; I attempted to compile and run `tests/app/SearchablePDF/main.swift` to get direct evidence, but the build command was denied by the permission mode, so no binary was built or run in this session.

### Geometry — re-derived, correct
`SearchablePDF.swift:87` maps a tile-normalized box to full-image bottom-left pixels as `(height - bottom) + box.minY * (bottom - top)`. `cropping(to:)` takes a top-left-origin rect, so `height - bottom` is the tile's bottom edge in image coordinates and `box.minY` is normalized to the tile's own height — exact in every strip, including the clamped first tile and a short final tile. Checked numerically against the test's 945×18000 fixture (`stripHeight = 2835`): the line at image-top offset 2805–2855 maps to physical y 15145 from both tile 0 (`[0,3027]`) and tile 1 (`[2643,6054]`), identically. `x` uses `image.width`, and every tile is full width, so x is strip-independent.

### Lost lines — the bug this commit targets
Tile *n* spans `[start−192, start+stripHeight+192]`, so consecutive tiles share a 384 px band and, since `stripHeight ≥ 1024`, no pixel row is in three tiles. Any line clipped at one tile's edge sits ≥ 384 px inside its neighbour, so it is fully observed at least once. Because `merged` starts empty and suppression is only ever against an *already accepted* line, every physical line retains at least one observation — the centre-filter loss mode at the old `SearchablePDF.swift:80-81` is genuinely gone.

### Dedup grouping — no duplication path found
Sorting by descending area at `SearchablePDF.swift:96` means the full observation is always considered before its clipped counterpart. A fragment is a subset of the full box, so `intersection ≈ 100% of smaller` clears the 0.65 gate and is dropped (`:101-102`). The same holds in the split/merged mismatch case (one strip emits `Total AUD 246.80`, the other splits it): the widest box wins and the pieces are absorbed. The `other.strip != line.strip` guard at `:98` correctly prevents adjacent printed lines from coalescing, and Vision emits no intra-call duplicates.

### Over-merging — checked and rejected
Suppression needs > 65% of the *smaller* area, i.e. vertical centres within 0.35 × box height. For two distinct printed lines to hit that you need axis-aligned boxes inflated by skew to ~3× the leading; at a realistic 2° skew on a 900 px-wide line the overlap is ~0.14, well under the gate.

### Other checks
- Original images untouched: `drawPDFPage(source)` at `:121` with the source `mediaBox` and `page.rotation = original.rotation` at `:149` — unchanged by this delta, and the pixel-equality/geometry preconditions at `tests/.../main.swift:106-108` still cover it.
- Reading order: the comparator at `:107` is byte-identical to the prior one and is a valid strict weak ordering; final order is fully determined by (midY desc, minX asc), so the unstable sort of `merged` introduces no nondeterminism.
- `docs/releases.md` — 0.4.2 / 8 Sep 2026 follows 0.4.1 / 7 Sep, matches `app/Info.plist:18`, and the searchable-text, geometry and DS-940DW-only claims match the code and `README.md:119`.

**Non-blocking, for awareness only:** the 0.65 area gate is the sole guard against duplicated text, and the two cross-strip observations of a boundary line must agree to within ~35% of line height. That margin is comfortable for identical pixel content, but if a future Vision version splits a row at different points in the two strips, a shared word could be emitted twice without any current assertion catching it. Not a defect in this delta.
