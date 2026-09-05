# Release notes

## 0.4.0 beta — 6 September 2026

- Adds an Apple Silicon DMG with a drag-to-Applications shortcut and offline setup notes. Includes a checksum-pinned Node runtime so AI filing does not need a separate Node installation. Explicit Node overrides remain available.
- Adds an app icon and a static GitHub Pages website with setup, privacy and compatibility details.
- Packaging allowlists worker resources and preserves upstream runtime bytes and license files.

This first DMG is ad-hoc signed and unnotarized. Developer ID signing and notarization are pending. Scanner behavior is unchanged from 0.3.9; Wi-Fi, long receipts, Auto cropping and blank detection retain their documented hardware limitations.

## 0.3.9 — 6 September 2026

- A failed filing or Undo no longer blocks later documents. Interrupted operations keep their target and can be retried when the original destination is available again.
- Incomplete and damaged queue records no longer hide healthy jobs. Inbox cleanup runs separately from successful filing; a cleanup warning preserves Filed status and offers its own retry.
- Preserves the preferred side count across long-paper/capability changes and keeps the saved provider model when opening AI settings. Optional startup crop errors leave recovered pages accessible.
- Moving a page switches to Single page view to show the actual PDF order.
- Codex verifies configured MCP servers are disabled using the pinned runtime, rejects unenumerated project config, and disables execution/integration features before classification. Unsupported runtime versions fail closed; blank runtime path uses the tested SDK default.

## 0.3.8 — 6 September 2026

Adds a second local blank-detection pass for cropped paper on a known scanner background. It follows skewed or curled borders and checks for connected ink strokes separately from broad, soft shadows and print-through. This addresses receipt backs retained by the earlier global ink-count check. The strict detector remains the first pass, and uncertain pages remain visible. Original images, restoration and existing draft edits are preserved; the change applies to newly received pages.

## 0.3.7 — 6 September 2026

Preserves the previous off default when upgrading without a saved blank-skipping preference. Remembers the selected paper mode across restarts, with A4 as the fallback until Auto is explicitly chosen. Rechecks paper capabilities after connecting, including when changing transports. These fixes supersede the initial local 0.3.6 test build.

## 0.3.6 — 6 September 2026

- Groups Paper, Sides, Options, Scan and Save in one control area. Connection and cleanup preferences live in Options; paper-size limits are explained beside the selection.
- Adds an experimental **Auto** request using the device-advertised AutoCrop extension, gated by simplex and duplex dimensions. Requests a 2550 × 4200 scan area. Scanner acceptance and actual cropping still need hardware validation; there is no automatic retry with another setting.
- **Skip blank pages** covers fronts, backs, single-sided scans and explicit imports. All-blank sheets remain recoverable; originals and the legacy blank-skip metadata key are preserved. Existing drafts are not reclassified.
- Device cropping is part of the delivered source image and cannot be undone locally. A4 capture with local border trimming retains the full acquisition area.

## 0.3.5 — 6 September 2026

- Adds **Paper → Long paper** for receipts up to 1.8 m, where advertised by the scanner. Selecting it turns off Both sides and shows straight-through paper-path guidance. Standard A4 duplex remains available.
- Carries paper mode through the shared scanner session and USB/Wi-Fi backend; rejects unsupported combinations before creating a scan job. Image transfers have a longer timeout.
- Tests cover capability scoping, both transports, option forwarding, and a maximum-length synthetic receipt through crop, restart, preview and PDF export. Physical long-paper validation remains pending.

## 0.3.4 — 6 September 2026

- Single-page view lists each front and back separately and adds Previous/Next navigation. Removing a back in paired view stays on the same sheet.
- Blank-back detection tolerates supported scanner-edge artifacts and faint, extended fold shadows. It still retains uncertain content, keeps original bytes, and offers restoration. Heavy print-through may still need manual removal.
- Auto-crop recognizes narrow scanner rims on nearly full-size sheets and cleans matching edge-connected scanner background, including around rounded card corners. Cleanup is reversible crop metadata; Full scan restores the original capture.

These changes apply to new captures or explicitly reapplied auto-crops. Existing drafts and edits are retained. The local build passed 70 offline scenarios; receipt/hardware calibration remains in progress.

## 0.3.3 — 6 September 2026

Removed the experimental **Possibly blank**, **Keep**, and **Remove back** prompts from local build 0.3.2. The existing page Remove control handles manual edits. **Skip blank backs** continues to hide clearly blank backs automatically, with originals retained and restoration available.

Automatic detection remains conservative: scanner borders, print-through and creases can still cause blank backs to be kept. This update removes the redundant prompts; it does not make detection more aggressive. Existing 0.3.2 drafts retain their pages and edits; obsolete suggestion metadata is ignored.

## 0.3.1 — 5 September 2026

Source update for local builds; no signed installer is published.

- Discover a Brother DS-940DW over Wi-Fi on the same local network, using the shared USB/Wi-Fi capture and document workflow. See [Wi-Fi setup](wifi.md).
- Optionally skip clearly blank backs of new duplex scans. The setting starts off; original images remain in the draft and **Restore this side** brings a skipped side back before saving.
- Use **Move earlier / Move later** to change individual PDF page order while the preview keeps each sheet's front and back together.
- Restore manually removed pages before automatically skipped backs when using the general restore control.

Existing drafts remain compatible. A local upgrade from 0.3.0 verified unchanged draft files and page visibility after reopening.

### Validation and remaining limits

All 67 offline scenarios and the feature-branch macOS CI passed. The merged application source matches the tested 0.3.1 build. The [validation guide](validation.md) describes coverage and physical scanner boundaries.

The Wi-Fi change completed independent review. Blank-back review found a restore-target bug that was fixed and regression-tested; the follow-up independent review timed out without a verdict. The timeout is not a review pass.

Blank detection has synthetic coverage, including scanner-sized faint marks, but still needs calibration against more real scans. It runs locally on the main thread; a scanner-sized blank fixture took about one second to classify in the current development build. Review skipped sides before saving.

Live API-key integrations, clean-machine setup beyond CI, public binary signing/notarization, dependency redistribution, and provider authentication eligibility remain release boundaries. See [validation](validation.md), [provider setup](providers.md), and [third-party notices](third-party.md).

Implementation and evidence: [Wi-Fi PR #1](https://github.com/kellygold/paper-in/pull/1), [blank-back PR #2](https://github.com/kellygold/paper-in/pull/2).
