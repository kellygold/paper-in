# Review triage

Candidate ccfe416295929c804dd27c9a8f5b9413f184124b. Claude Opus, high effort, read-only; completed in 352.8 seconds with no P0/P1 findings.

Non-blocking notes were checked against the production control flow:

- Numeric DNS errors: confirmed usability limitation. The session pauses and requires Connect; this is consistent with avoiding automatic retry loops. No data loss or extra scan.
- One discovery candidate per connection: confirmed. A failed resolve pauses the session and releases its references; it does not silently switch devices. Multiple-device selection/fallback is future scope.
- Transport picker/inner busy-guard divergence: no reachable production trigger reproduced. The private backend's only path to busy is ScannerSession.scan(), which refreshes its state synchronously, and the picker is disabled while busy. Retained as a future hardening note, not treated as an observed race.
- Device identity and HTTP: expected limitation of local unauthenticated discovery, explicitly documented. Model checks are compatibility checks, not cryptographic authentication.

No reviewer patches were applied. Hardware execution, privacy/static audit and automated tests were separate evidence lanes; the reviewer did not claim to have run them.
