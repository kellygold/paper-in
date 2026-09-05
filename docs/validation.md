# Validation

Status: local 0.3.9 build verified on 6 September 2026; source release, not a signed installer.

## Automated checks

`./test.sh` builds the application and passes 91 offline checks (64 native, 27 worker) without contacting scanners or providers.

- 13 draft/PDF scenarios: original-byte retention, restart and same-process recovery, interrupted capture/export, collision refusal, edits, 40-page documents, image orientation, explicit sheet pairing, legacy pages and durable AI handoff.
- 5 eSCL transport scenarios: rejected jobs, foreign job URLs, complete image/PDF delivery, incomplete images and status parsing (some assertions share a scenario).
- 5 crop scenarios: cards, receipts, blank pages, physical PDF sizes, scanner padding, reversible metadata and unchanged original bytes.
- 1 maximum-length receipt scenario: retains both ends through crop, restart, preview and one tall PDF, with original bytes preserved.
- 12 blank-page scenarios: white/noisy paper and specks; faint, tiny, edge and coloured marks; uncertain backgrounds; either-side, simplex and import skipping; all-blank drafts; unchanged originals; PDF page counts; restoration, restart and interrupted-ingest recovery; skewed receipt silhouettes and broad shadows with crop enabled or disabled.
- 2 legacy ImageCapture connection scenarios retained as regression fixtures.
- 4 shared scanner-session contract scenarios: capabilities, scan options, ordered pages, consumer storage failure, pause and transport replacement without losing draft callbacks.
- 15 scanner transport scenarios: local endpoint validation plus shared USB/Wi-Fi duplex delivery, duplicate-start prevention, missing-back preservation, empty/jammed feeder refusal, wrong-model rejection and stale discovery callbacks.
- 7 native application-flow scenarios: paired selection, per-side edit/removal/restoration, adding another sheet and saving a four-page PDF; capture callbacks skip a blank back, update previews, restore that exact side and save both pages; side preferences across paper modes, visible order after moving a page, recovered legacy pages after crop failure and the saved model in the mounted settings view.
- 27 worker scenarios: idempotent export discovery, both classification passes, mandatory review, failed/retried analysis, malformed outputs, traversal/symlink rejection, output collisions, interrupted publication/Undo, changed-file preservation, stale locks, corrupted originals, provider registry consistency, both API wire formats, incomplete responses, missing credentials/rate limits and credential-safe errors. Recovery tests cover unavailable destinations during publishing/Undo, malformed or incomplete records, retryable inbox cleanup and Codex tool isolation across TOML syntax without starting configured commands.

## Live synthetic tests performed

All documents below were generated fixtures; no personal scans were sent. The 0.3.9 pass repeated Codex classification and the native controller → packaged worker → local OCR → live Codex → filing → Undo path, including restored-PDF hash equality and temporary Keychain cleanup. Claude live results below are earlier checks of its unchanged adapter; live API-key services remain untested.

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

The original scanner path had real single/duplex DS-940DW USB captures confirmed. Version 0.3.0 shares that job lifecycle between USB and Wi-Fi discovery. On 5 September 2026, the production Wi-Fi backend, image validation, crop, draft store and PDF exporter captured both sides of a user-loaded sheet and saved a two-page PDF. This used an isolated native harness, not the main window; the scanned content is retained only locally and is not a repository fixture.

The Wi-Fi device initially reported `ScannerAdfJam`; the backend refused to create a job. A physical reboot cleared it to `ScannerAdfLoaded`, after which one explicit capture succeeded. The normal internet route was unchanged. Other models, the physical Start button, long receipts, unplug/replug and sleep/wake remain unverified.

After running the offline tests, `.build/scanner-transport-tests --live-discovery` performs an opt-in, read-only Bonjour/capability check. It never starts a scan or touches the user's draft.

## Repository organization verification

The `app/`, `ai/`, and unified `tests/` layout passed all 47 existing automated scenarios on 5 September 2026. The opt-in native controller → packaged worker → local OCR → Codex → filing → Undo check also passed after the move, including temporary Keychain store/read/remove. No application logic or on-disk document format changed.

`./scripts/live-native-test.sh` reproduces the packaged-worker check using generated content and the existing Codex login. It consumes provider quota and retains evidence under `.build/live-native-*`.

## Before a public binary release

- Verify a fresh physical single-sided and duplex scan using the new build, including missing-back behavior and restart recovery.
- Run live API-key checks for the selected default/example models.
- Validate build instructions on a clean supported Mac, then complete Developer ID signing/notarization and dependency redistribution review.
- Confirm the public app's provider authentication eligibility; technical success does not resolve provider terms.
- Publish a compatibility list with observed hardware results, not inferred support.

## Auto paper and general blank skipping (0.3.6 candidate)

The scanner's advertised AutoCrop flag and per-source dimensions gate an experimental Auto request. Offline fixtures verify the request on both transports and reject it when unsupported. This does **not** prove the firmware honors the crop flag. Actual image bounds, edge quality and extra-long behavior require physical scanning; no unattended scan is part of these checks.

General blank-skipping tests cover blank fronts with printed backs, both sides blank, simplex/imports, disabled cleanup, restoration after restart, and rejection of empty PDF export. The application flow also clears stale previews when all pages disappear. The new controls separate paper/sides choices from cleanup and connection preferences.

## Shadowed receipt backs (0.3.8 candidate)

A second local classifier runs only after the strict check retains a cropped item on a known scanner background. Synthetic regressions exercise diagonal paper edges and soft fold shadows, both crop settings, tiny and edge ink, faint pencil-like strokes, coloured marks and text. The existing strict detector remains in place for clean or uncertain paper.

Two previously captured receipt pairs were replayed locally through production ingestion: both printed fronts remained and both blank backs were skipped. Restart, restoration and one-page PDF export were verified, with input and retained original bytes unchanged. Those personal images are not repository fixtures. No scanner job or provider request was started for this verification. Fresh physical capture with the installed candidate still needs user confirmation.
