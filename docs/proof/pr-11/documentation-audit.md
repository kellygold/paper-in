# PR 11 documentation and issue-form audit

Candidate 649a66b6adf0dc6aeece5e33eb7ea6c2ac57764c, base eea87eff670f8fba81458637eed657f37cd5b1fc. Independently confirmed clean HEAD in the provided .build/domain-followup worktree. Local checks completed 2026-09-07T14:28:00Z. Scope: nine changed documentation/template/static-URL files only.

## Finding
Minor checklist correction at docs/scanner-testing.md:17: it tells volunteers to save one PDF and then reopen to check draft recovery, but README.md:52 explains saving starts a fresh document. Reopen and verify the unfinished 5/10/15-page draft before the final Save PDF, then verify the exported PDF. This makes the promised recovery check meaningful. No code or hardware defect is implied.

## Passed checks
- 52 relative file, Markdown anchor, GitHub repository-file, and custom-domain-to-local-site references resolve in the candidate. Custom-domain mapping checked only that /, /install.html and image paths correspond to existing site files; it is not live domain validation.
- YAML safe_load succeeds for .github/ISSUE_TEMPLATE/scanner-compatibility.yml. Seven body entries include six unique valid IDs, three required input/dropdown fields, supported field types, nonempty labels/options and a valid checkbox label. Shape checks found no issue. The referenced scanner-testing.md exists.
- DS-940DW-only support remains explicit in README, the new checklist and issue form. The issue form says reporting does not enable a different model. The checklist rejects model-name/capability-only compatibility claims and unsupported-model bypasses, separates USB/Wi-Fi evidence, and requires maintainer review before supported status.
- Volunteer work is bounded to fictional documents and an isolated draft; it requests redacted diagnostics only, excludes personal data/credentials/network identifiers, follows manufacturer-supported sizes, and explicitly forbids deliberately jamming/damaging hardware. New feeder/flatbed behavior is not assumed to match the DS-940DW contract.
- Updated 0.4.1 packaging filename agrees with candidate Info.plist version. Architecture review-policy wording matches the existing documented same-vendor versus duplicate/continuation boundaries without changing code.
- git diff --check passed. Domain substitutions preserve relative assets and point canonical/OG/home links to matching candidate site routes.

Commands: git rev-parse HEAD; git status --short; git diff --stat and git diff base..HEAD; Python standard-library link/anchor mapping plus installed PyYAML issue-form shape validation; git diff --check base..HEAD. Detailed structured result: local-checks.json.

## Cleanup and boundaries
Only this receipt and local-checks.json created under ignored .build/domain-doc-audit. Provided worktree left untouched; no temporary worktree or process to clean up. No user data, app, scanner, providers, Keychain, DNS, network or GitHub writes. Nineteen external release/PR/vendor links were not requested. Live DNS/TLS, redirects, deployed website, GitHub-rendered form and release-evidence claims remain root-owned external checks. No broad application re-review or delegation.
