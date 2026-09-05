# App-ticket packaging delta audit

HEAD df91266aba907d7bc27d1ef716f1393938efb94e independently confirmed clean. Delta from a09382b: scripts/package-dmg.sh and docs/distribution.md. Mock run completed 2026-09-05T23:07:58Z. Exact tested script SHA256 1e06c8322f20298fca031e4f90679a3e75e661cc0c70938b180ea195cdc40a92.

## Result
No concrete bug found in this bounded delta. Eighteen mocked contract cases passed. The script now fails closed on app notarization/ticket/policy failures before constructing the DMG, while retaining the existing DMG-stage gates.

## Evidence
- scripts/package-dmg.sh:8–10 shared paper_notarize helper retains set -euo pipefail behavior when called as a normal top-level command. Both app and DMG submissions reject Invalid, timeout exit75 and malformed JSON; neither can bypass exact Accepted status.
- :42–47 writes the signed payload ZIP, requires its acceptance, staples/validates the application ticket and runs syspolicy_check distribution before DMG construction. Each app invalid/timeout/malformed/staple/validate/policy failure prevented any hdiutil create call and retained its ZIP/receipt where created.
- Successful call trace confirms app submit < app ticket validate < syspolicy_check < DMG construction < DMG submit. Exactly two notary submissions occurred. The temporary app ZIP is removed only after the app checks pass.
- DMG invalid/timeout/malformed/staple/validate/signature/Gatekeeper failures all prevented promotion to the new release filename. Missing identity/profile and initial signature checks still fail early. Success alone produced final DMG/checksum; an existing older release remained unchanged after a later failure.
- docs/distribution.md accurately distinguishes app and DMG receipts, explains the copied app's stapled ticket, and describes retained current payloads after failures. It continues to require actual accepted/verified artifacts before public installation claims.

Commands: bash -n scripts/package-dmg.sh; git diff --check a09382b..HEAD; python3 .build/signing-audit/contracts-app-ticket.py. Eighteen fixture copies were byte-identical to the pinned script. Call-order assertions passed.

## Limitations and cleanup
All Apple, signing, ticket, policy, DMG and Node operations were mocked. This checks control flow, status parsing, retained filenames, success ordering and negative gates; it does not establish real acceptance/ticket validity for df91266. Root owns current real notarization, final bundle checks and full tests. No Keychain, credentials, network, private documents, scanner or installed app accessed. The real packaging run and its authorization prompt were left alone.

Removed the entire isolated app-ticket-sandbox after preserving app-ticket-contracts.json, contracts-app-ticket.py, audited-app-ticket-package-dmg.sh and this receipt. No source edits, commits, publishing or agent delegation.
