# Queue dismissal and review-policy validation

Candidate 7e01abd7b3d7e9d11f268625165d617260ee2aae; base d2830638338e8662d290fd79675eeb55884a1a0d; PR10. Candidate source and dedicated detached worktree both independently confirmed clean at pinned HEAD. Completed 2026-09-07T09:52:40.427140+00:00.

## Findings
No concrete bug found in the scoped dismissal/recovery, removed-PDF, and review-policy contracts. This is a bounded validation result, not a broad code review or real-provider assessment.

## Checks passed
- Existing engine suite: 25/25 tests passed, 0 failed, ~2.1 seconds.
- Independent bounded probes: 21/21 passed, 0 failed, ~1.3 seconds. Includes a nine-condition conservative-review matrix within the final scenario.
- Dismiss/restore through fresh FilingEngine instances, discovery and run preserves queued, analyzing→queued, review, failed, missing and undone states. Dismissal is idempotent, blocks provider callbacks while hidden, and retains source/recovery bytes. Actual filed entry dismissal/restoration retains its published PDF without another analysis.
- Mixed bulk dismissal leaves publishing and undoing records byte-equivalent in state/target/undo metadata. Direct dismissal of either rejects; eligible queued entry is dismissed and retained PDFs remain unchanged. Restart/discovery does not recreate dismissed jobs.
- External deletion and Finder-style move of queued PDFs results in missing state and zero provider callbacks, including after dismiss→restart→restore→retry. No replacement PDF is created. Deleted review originals cannot be applied. Deletion during synthetic analysis blocks publication. Deleted filed targets stay absent after run/discovery/dismiss/restoration.
- Same-vendor separate-purchase relationship can auto-file when all other gates pass. Duplicate, continuation, uncertain and unknown legacy relationship labels require review with actionable reasons. First-pass continuation cannot be erased by second-pass same_vendor; exact-byte context duplicates still require review. First/second human-check flags, low confidence, weak OCR, truncated document, partial library, new category and proposed-name disagreement remain review gates.

## Code boundaries inspected
- ai/engine.mjs:269–301 dismissal stores prior state, rejects unfinished transactions, bulk-skips publishing/undoing, restores existing record and supports rechecking review/missing states.
- ai/engine.mjs:100–106 and :182–183 detect absent original before analysis/publication. Existing filed jobs do not automatically recreate deleted targets. Explicit Undo and already-owned transaction recovery retain their existing recovery semantics; tests here do not redefine those as externally deleted queued documents.
- ai/review-policy.mjs:1–14 combines both AI passes and independent context safeguards; same_vendor only exempts that relationship from the related-document gate. It is not a blanket waiver.
- ai/main.mjs exposes dismiss/dismissAll/restoreEntry inside the existing worker lock. Dispatch read statically; no real provider SDK process was launched.

Commands: git worktree add --detach .build/ux-queue-audit 7e01abd7b3d7e9d11f268625165d617260ee2aae; node --test tests/ai/engine.test.mjs (inside worktree); node --test .build/ux-queue-audit-evidence/probes.mjs. Logs: existing-engine-tests.log, bounded-probes.log; independent harness: probes.mjs. No npm installation or network request.

## Cleanup and unvalidated scope
All independent fixtures were isolated under .build/ux-queue-audit-evidence/fixtures and removed by test teardown; directory verified empty then removed. Existing engine test fixtures also use their own teardown. Dedicated detached worktree removed after preserving evidence. No candidate source edits, user scans, installed app, Keychain, scanner, real provider or release/GitHub writes. Actual native views, mounted application, performance, package, CI and different-lab review belong to the other lanes. Real model judgments about whether two purchases are separate remain unvalidated; only deterministic policy handling of supplied classifications was exercised.
