# Validation

Status: local build verified on 5 September 2026; not a public signed release.

## Automated checks

`./test.sh` builds the application and runs native and worker tests without contacting scanners or providers.

- 13 draft/PDF scenarios: original-byte retention, restart and same-process recovery, interrupted capture/export, collision refusal, edits, 40-page documents, image orientation, explicit sheet pairing, legacy pages and durable AI handoff.
- 4 eSCL transport scenarios: rejected jobs, foreign job URLs, complete image/PDF delivery, incomplete images and status parsing (some assertions share a scenario).
- 4 crop scenarios: cards, receipts, blank pages, physical PDF sizes, scanner padding, reversible metadata and unchanged original bytes.
- 2 legacy ImageCapture connection scenarios retained as regression fixtures.
- 2 shared scanner-session contract scenarios: capabilities, scan options, ordered pages, consumer storage failure and pause.
- 1 native application-flow scenario: paired selection, per-side edit/removal/restoration, adding another sheet and saving a four-page PDF.
- 21 worker scenarios: idempotent export discovery, both classification passes, mandatory review, failed/retried analysis, malformed outputs, traversal/symlink rejection, output collisions, interrupted publication/Undo, changed-file preservation, stale locks, corrupted originals, provider registry consistency, both API wire formats, incomplete responses, missing credentials/rate limits and credential-safe errors.

## Live synthetic tests performed

All documents below were generated fixtures; no personal scans were sent.

| Check | Result |
| --- | --- |
| Claude Agent SDK, existing subscription login, structured invoice classification | Passed |
| Codex SDK, existing ChatGPT login, structured invoice classification | Passed |
| Swift-exported image PDF → local OCR → Claude → filing → Undo | Passed; original PDF hash preserved |
| Swift-exported image PDF → local OCR → Codex → filing → Undo | Passed; original PDF hash preserved |
| Native FilingController → bundled Node worker/runtimes → OCR → Codex → file → Undo | Passed |
| Native Keychain store/read/remove using a temporary synthetic value | Passed |
| OpenAI and Anthropic API-key requests against real services | Not run: no API keys configured. Request/response and failure tests passed using controlled responses. |

The provider may vary its exact filename or misread OCR. A successful synthetic test establishes the integration path, not universal classification accuracy or subscription eligibility.

Repeat opt-in end-to-end tests with:

```sh
./scripts/live-test.sh codex
./scripts/live-test.sh claudeSDK
# API tests additionally require the matching API key and PAPER_IN_TEST_MODEL:
./scripts/live-test.sh openaiAPI
./scripts/live-test.sh anthropicAPI
```

Tests retain generated evidence under `.build/live-*`. This directory is ignored by Git. API keys are supplied through the environment for these command-line tests only; the production Mac UI uses Keychain.

## Visual and hardware boundaries

The paired preview, settings and review screens are checked using demo mode and synthetic pages. Preview artifacts live under `.build` and contain no personal documents.

The 0.1.4 scanner path had real single/duplex DS-940DW captures confirmed. Version 0.2.0 reorganizes that same transport/profile behind a shared scanner interface; its automated tests pass, but a fresh physical capture in the new build still needs the user to feed a sheet. No other model, Wi-Fi, physical Start button, long receipt, unplug/replug or sleep/wake compatibility claim is added by this work.

## Repository organization verification

The `app/`, `ai/`, and unified `tests/` layout passed all 47 existing automated scenarios on 5 September 2026. The opt-in native controller → packaged worker → local OCR → Codex → filing → Undo check also passed after the move, including temporary Keychain store/read/remove. No application logic or on-disk document format changed.

`./scripts/live-native-test.sh` reproduces the packaged-worker check using generated content and the existing Codex login. It consumes provider quota and retains evidence under `.build/live-native-*`.

## Before a public binary release

- Verify a fresh physical single-sided and duplex scan using the new build, including missing-back behavior and restart recovery.
- Run live API-key checks for the selected default/example models.
- Validate build instructions on a clean supported Mac, then complete Developer ID signing/notarization and dependency redistribution review.
- Confirm the public app's provider authentication eligibility; technical success does not resolve provider terms.
- Publish a compatibility list with observed hardware results, not inferred support.
