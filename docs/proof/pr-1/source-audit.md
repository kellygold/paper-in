# Source package audit receipt

Candidate: `ccfe416295929c804dd27c9a8f5b9413f184124b`
Base: `91458981310915e24846a19ee9b222d6999f8450`
PR: https://github.com/kellygold/paper-in/pull/1
Target: `/Users/kgold/Code/paper-in-wifi-review`, native macOS source; no web deployment.
Completed UTC: 2026-09-05T12:47:20.341926+00:00

## Commands / actions

- `git status --porcelain`, `git rev-parse HEAD`: exact candidate, clean before and after.
- `git diff --stat BASE..HEAD`, `git diff --numstat BASE..HEAD`: 20 files, +614 / -110; 9 feature, 3 test (including test wiring), 2 workflow/config, 6 docs.
- `git ls-files -z` and `git ls-files --stage '*.sh'`: 76 files, documented executable entrypoints executable.
- `git rev-list --objects --all`, `git cat-file -t OBJECT`, `git cat-file blob OBJECT`: inspected 123 reachable blobs / 879,334 bytes using redacted patterns for provider/private keys, JWTs, embedded URL credentials, personal absolute paths, email addresses, credential assignments, MAC addresses and standalone eight-digit hex values. Zero findings. Pattern scanning is bounded detection, not a guarantee against arbitrary secrets.
- Python relative Markdown target resolution: 53 local file links, zero broken targets (anchor semantics and external links not tested).
- Tracked artifact scan: zero PDFs, image scans, credential files, dependency trees, app bundles, disk images, archives or logs. No tracked file exceeds 1 MiB. Only binary is the 257,199-byte generated preview PNG.
- `view_image docs/images/paired-preview.png`: generated Paper In sample pages, no personal document content. Demo temporary output path appears in image.
- `bash -n build.sh test.sh scripts/*.sh`: pass.
- `plutil -lint app/Info.plist`: pass.
- `git diff --check BASE..HEAD`: pass.
- JSON parse / equality for `ai/package.json` and `ai/package-lock.json`: dependency and package version match.
- Read README, project map, architecture, development, contributing, Wi-Fi, providers, third-party, validation and historical scope against build/test entrypoints. Physical scan limitations and lack of signed installer documented. Historical plan explicitly labelled historical.

## Findings / limits

No blocker found within this static source-package lane. Native app is 0.3.0 while worker package and Claude client identifier remain 0.2.0; separate worker versioning is possible, but release reporting should be intentional.

No full build or runtime test executed in this lane. Scanner lifecycle, physical hardware, AI providers, remote external link validity, licensing/legal eligibility and binary redistribution readiness were not evaluated here. The repository documentation itself marks those release boundaries. No universal absence-of-secrets guarantee is made.

## Cleanup

Candidate remains unchanged and clean. No scanner/provider calls, app launches, credential reads, settings changes, publication or merging. No synthetic external state created. Only this receipt and the two JSON evidence files were written under the assigned `.build/source-audit/` directory.

## Evidence checksums
- `static-audit.json` SHA-256 `03e960bc512c8cec91f119cd6682f30e095acb53fc6b453035707859cd9561d7`
- `entrypoint-audit.json` SHA-256 `ec7589b6f7bd141b13b2dec3bdfb096b95170f0949929063c42241479befa7ef`
