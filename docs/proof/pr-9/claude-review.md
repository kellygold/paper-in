# Independent release review

Candidate: `df91266aba907d7bc27d1ef716f1393938efb94e` against `6c9425e90b5c538991c268996b6ea01d9815e476`. Claude Opus, high effort, read-only clean worktree, no subagents. Completed in 328.1 seconds.

## Verdict: no release-blocking findings

I reviewed HEAD `df91266` against base `6c9425e` on a clean worktree (`git status --porcelain` empty). What I re-derived, independent of the reported test results:

**Signing/notarization boundaries** (`scripts/package-dmg.sh`) — ordering is correct at every gate: Runtime/Notices resources are copied *before* signing (`:29-35`), helper is signed before the outer bundle (`:37-38`), and app notarize→staple→`syspolicy_check` precedes DMG creation (`:42-47`), so the app copied to /Applications carries its own ticket. `paper_notarize` (`:7-10`) doesn't rely on `notarytool`'s exit code; the `plutil`/`grep -qx Accepted` check under `pipefail` is the real gate. Candidates stay under `.unnotarized` names until every gate passes (`:57-62`), so a timeout or rejection cannot produce the release filename or a matching `.sha256`.

**Vendor signature preservation** — dropping `--deep` in `build.sh:26-27` and `scripts/live-native-test.sh:19` is what leaves upstream Node/provider binaries with their own signatures; only PaperOCR and the outer bundle are re-signed, which matches what notarization needs and what `docs/third-party.md:11` claims.

**Missing runtime resources** — I checked the new rsync allowlist (`build.sh:23`) against `git ls-files ai/` plus the working tree: `providers/`, all seven top-level `.mjs`, `package.json`, `package-lock.json`, `provider-catalog.json` and `node_modules` are all matched; only `ocr.m` (compiled separately) and dot-files like `.env` fall through `--exclude '*'`. `scripts/make-icon.swift:34-40` emits all ten filenames `iconutil` requires.

**Clean-Mac install journey** — `FilingController.swift:93` puts the bundled path after the explicit override and behind an `isExecutableFile` check with an empty-string guard, and `FilingController.swift:160-163` prepends `Runtime/bin` to the worker's PATH. That matters: `codex-isolation.mjs:51` uses `process.execPath`, but the Claude SDK resolves its own `node`, so on a Mac with no Node installed both providers still resolve — the "you do not need to install Node separately" claim in `site/install.html:111-112` holds.

**Shipped-file and claim checks** — `site/install.html` is fully self-contained (inline `<style>`, no `<link>`/`src`), so the DMG's offline `Start Here.html` renders without the site assets. `site/assets/app-preview.png` shows only demo-mode synthetic pages and a temp path. Download URLs (`site/index.html:52,215`) match `Paper-In-0.4.0-arm64.dmg` derived from `CFBundleShortVersionString` 0.4.0. Signed/notarized wording is backed by hard gates, and the privacy wording ("extracted text and related excerpts" sent, page images local) matches the worker's actual behavior.

**Pages ordering** — `.github/workflows/pages.yml` uploads only `site/` with pinned SHAs and least-privilege tokens; the release-before-deploy requirement is encoded in `docs/distribution.md` step 3. That's a manual sequencing step, not a defect in the change.

One non-blocking note, no action needed for release: `site/index.html` says "Free & open source" (`:92,303`) without a third-party-notices link, while the DMG bundles the proprietary Claude runtime. The claim is accurate about the project's own MIT source, and `install.html:153` plus `Contents/Resources/Notices` carry the notices — P2 at most.

Coordinator triage: no blocking finding. Optional homepage notice link is deferred; the installation page and bundle already link/include third-party notices. Fresh-Mac compatibility reasoning is code review, not a fresh-machine execution claim.
