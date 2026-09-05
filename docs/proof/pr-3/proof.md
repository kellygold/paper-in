## Outcome

**Partially validated** — candidate `752833b2aeef85d87ba4e6908a02253ba478790d` tested in isolated local native harnesses and macOS CI.

Near-blank duplex backs offer Keep/Remove back; suggestions stay visible and exported until explicitly removed. Automatic skipping remains conservative.

## Scope and topology

- PR: https://github.com/kellygold/paper-in/pull/3
- Candidate: `752833b2aeef85d87ba4e6908a02253ba478790d`; base `ccb7da490c986554376f0a723d916ba9a41e8875`.
- Target: local 0.3.2 build 9; generated demo fixtures and isolated private-image replay.
- Client/candidate boundary: detector, draft metadata, paired preview and tests.
- Stable/unchanged boundary: scanner transport, AI workers, provider authentication and PDF exporter.
- Explicitly excluded: active user draft writes, live scanner jobs, AI calls, publication of private images, installed app replacement.

## Client-side proof

![Generated suggestion preview](https://github.com/kellygold/paper-in/blob/proof/pr-3/docs/proof/pr-3/suggestion.png?raw=true)

- Workflow: production capture callbacks receive generated front/back, render a suggestion, invoke the existing exact-side remove action, and render the removed side.
- Visible result: Keep/Remove back with the full page visible; subsequent Side removed and Restore this side.
- Network result: NONE; local native application.
- Boundary: screenshots use candidate SwiftUI views and production AppModel in an isolated harness. These are rendering/model-action evidence, not interactive clicks in the installed application. The initial harness assertion assumed selection stayed on a removed page's sheet; it was corrected to select the front before removing the back. Candidate code did not change.

## Backend assertions

```text
record: generated suggestions/suggested-export-copy drafts in BlankPages suite
expected: possibleBlankBack=true on known duplex back; removed=false; both sides visible
restart: suggestion persists
export: suggested back remains in two-page PDF
Keep: clears suggestion without removing page
Remove/Restore: exact side changes; originals retained
```

## End-to-end flow

- Trace: [sanitized private replay receipt](https://github.com/kellygold/paper-in/blob/proof/pr-3/docs/proof/pr-3/private-replay-receipt.txt).
- Real action: `DraftStore.ingest → restart → export` using three existing scanner back images, each replayed as a test duplex pair.
- Resolved request: `autoCrop=true, skipBlankBacks=true, expectedSides=2`.
- Result: all three backs produce suggestions, retain two visible sides and two PDF pages; input and retained bytes unchanged.
- Final state: isolated test outputs removed; user originals unchanged. No new physical scan was requested.

![Generated removed-side preview](https://github.com/kellygold/paper-in/blob/proof/pr-3/docs/proof/pr-3/removed.png?raw=true)

## Negative-regression proof

- Scenario: tiny/faint/edge/coloured/light-on-grey ink, disabled/simplex/unpaired scans, exact restoration, interrupted ingest recovery, and suggestion PDF inclusion.
- Result: passed in native suites; automatic skipping thresholds remain unchanged.
- Forbidden side effects: 0 scanner jobs and 0 provider requests; no installed-app replacement or user-draft mutation.

## Automated gates

- Focused tests: 8 blank-page and 3 native application-flow scenarios.
- Repository gates: 69 total scenarios (48 native, 21 worker), local build and signature verification passed; `git diff --check` passed.
- CI: passed — https://github.com/kellygold/paper-in/actions/runs/33970399115
- Static audit: 79 tracked files; 61 local Markdown file links, none broken; no tracked scan PDFs, dependencies, credential files or high-confidence secret-pattern matches. Not a historical secret audit.

## Validation lanes

| Lane | Owner | Status | Receipt |
|---|---|---|---|
| Automated/static | Codex and bounded source-audit agent | Passed | [Offline checks](https://github.com/kellygold/paper-in/blob/proof/pr-3/docs/proof/pr-3/offline-tests.txt) |
| Deployed client | Codex | Skipped | Generated candidate UI above; installed-app interactions not run |
| Backend/integration | Codex | Passed | [Receipt](https://github.com/kellygold/paper-in/blob/proof/pr-3/docs/proof/pr-3/receipt.json) |
| Different-lab review | Claude Opus, high | Passed | [Review: no P0/P1 defects](https://github.com/kellygold/paper-in/blob/proof/pr-3/docs/proof/pr-3/independent-review.md), 362.1 seconds |

All lanes reference candidate `752833b2aeef85d87ba4e6908a02253ba478790d`. No claim of a fresh physical scan or installed-app interaction.

## Deploy-time manual steps (env/secret/flag parity across BOTH origins)

- Env vars / secrets / flags this PR needs: NONE. Existing Skip blank backs preference remains off by default.
- Applied where, by whom, when: NONE; local Mac application only, no Cloud Run/Replit origins.
- Safe-when-absent check: optional stored metadata decodes as nil; existing setting absence remains disabled.
- Post-deploy reconfirmation: pending installation; no deployment performed.

## Safety, cleanup, and release decision

- Synthetic scope: generated native fixtures; three private scans read locally only, with no uploaded images.
- Provider delivery status: not applicable; no provider requests.
- Cleanup: temporary replay roots, successful demo roots, and the failed generated preview fixture removed. Evidence retained under ignored .build and this separate proof branch.
- Restored configuration: no user configuration or installed app changed.
- Known limits: sparse writing can receive a review suggestion; controls appear only in paired layout; the banner offsets the back preview vertically. Review found no blocking defects. Minor documentation omissions remain in the test-scenario summary.
- Unvalidated: fresh hardware capture and interactive installed-app workflow; broader scanner calibration. This change does not automatically remove the three ambiguous backs.

**Partially validated: installed-app interaction and a fresh hardware capture have not been performed.**
