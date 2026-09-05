# Release notes

## 0.3.2 — 5 September 2026

Near-blank backs now offer **Keep** and **Remove back** in the paired preview. Scanner borders, folds, and faint print-through can resemble ink to the conservative detector; these suggestions stay visible and remain in exported PDFs until explicitly removed. Clearly blank backs still skip automatically, with originals retained. The setting applies to new duplex scans only.

Three locally replayed scanner backs with paper-edge shadows, folds, or print-through now produce review suggestions. Those private images are not repository fixtures. Automated fixtures cover the same classes of marks, persistence, PDF inclusion, explicit removal and restoration. Automatic skipping remains conservative; this change does not automatically discard these ambiguous backs.

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
