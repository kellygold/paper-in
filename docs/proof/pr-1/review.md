## Result: no release-blocking P0/P1 findings

I re-derived the intended behavior from the diff and read the production sources rather than the tests. Nothing I found rises to P0/P1.

### What I checked and why it holds

**Discovery callbacks / stale sessions** — `ESCLScannerBackend.swift:51-62` captures `token = generation` and every entry point back into the backend (`onEndpoint`, `onError`, the deferred `stopDiscovery` at `:100-103`, and the capability `Task` at `:104-121`) re-checks it. `pause()` (`:84`) rotates the generation, so a late capability response or a late discovery callback from a prior connect is dropped. The one gap — `onError` at `:58-62` checks `generation` but not `listening` — is unreachable in practice because the only way to be connected with a live browse ref is the sub-millisecond window before the `:100` async block runs, and `pause()` rotates the generation on every other path.

**Device-controlled endpoint/path/HTTP data** — `ScannerEndpoint.make` (`ScannerDiscovery.swift:15-56`) is the right shape: port range, USB pinned to loopback, network pinned to a `.local` suffix with an explicit lowercase-alnum/`-`/`.` byte allowlist, and the `rs` path restricted to non-empty segments excluding `.`/`..`, with `//` rejected on the *untrimmed* string and `%` outside the allowed byte set (so `%2e%2e` cannot smuggle a traversal). The URL is rebuilt via `URLComponents` with a fixed `http` scheme, so no userinfo/query/fragment survives. `ESCLClient.create` (`ESCLClient.swift:88-98`) still pins the `Location` job URL to the same scheme/host/port and requires the `base.path + "/ScanJobs/"` prefix, which now correctly follows a device-supplied `rs` base rather than a hardcoded `/eSCL`. Redirects remain refused (`ESCLClient.swift:5-11`).

**Transport replacement with an existing draft** — `ScannerSession.replaceBackend` (`ScannerBackend.swift:64-74`) keeps the session identity, which matters because `ContentView` holds `@ObservedObject var scanner: ScannerSession` (`ContentView.swift:7`) as a stored reference. `bindBackend()` re-wires `onCaptureBegan/onImage/onCaptureEnded` into the same `onBegin/onPage/onEnd` closures `AppModel` installed once at init (`AppModel.swift:73-95`), so the draft callbacks survive the swap. Old callbacks are nil'd and the busy guard is on the *old* backend's snapshot.

**Failure boundaries moved out of the USB backend** — the jam/empty/unknown feeder throws (`ESCLScannerBackend.swift:149-159`) all occur *before* `onCaptureBegan` (`:162`), so a refused feeder state never opens a draft capture and never POSTs a job. That is the correct boundary.

**Ambiguous ownership / duplicate jobs** — `scan()` sets `busy = true` synchronously at `:130` under the `!busy` guard at `:124`, and `ScannerSession.scan()` refreshes synchronously, so a double click cannot open a second job. `ownedJob` is closed on every exit path (`:184-190`).

**Preserving a front when the back fails** — a mid-loop failure at `:175` leaves `received == 1`, `began == true`, so `onCaptureEnded(false, …)` runs and `DraftStore.completeCapture(success: false)` (`DraftStore.swift:145-150`) only sets `interrupted`; the ingested front page is retained.

**USB regression** — the USB path is behaviorally equivalent: same `kDNSServiceInterfaceIndexLocalOnly` + `_ippusb._tcp`, and the new host check accepts a superset of the old `localhost`/`localhost.`/`localhost.local.` set. The `resolveRef == nil` single-resolve gate and the deferred deallocation both existed in the base. Build wiring is glob-based (`scripts/project.sh:4`), so the rename and the two new files are picked up.

### P2 notes (not release-blocking)

- `ScannerDiscovery.swift:96-99` — a nonzero browse error now calls `fail()` and pauses the whole session, where the base silently ignored it and kept browsing until the 12 s timeout. On `kDNSServiceInterfaceIndexAny` (Wi-Fi), transient browse errors are more likely than on the USB local-only pseudo-interface, and the user sees a bare numeric code. Recoverable via **Connect**.
- `ScannerDiscovery.swift:100-102` with `:153-161` — `resolveRef` is only cleared in `stop()`. A resolve that errors or yields a rejected endpoint leaves it set, so no other advertised instance is attempted for the rest of that discovery session. This gate was written for the single-instance local-only browse and is now applied to a multi-interface browse. Impact is bounded because the resolved host is a name, so different interfaces normally yield the same usable URL.
- `AppModel.swift:127-133` — `changeConnection` guards on `scanner.busy` but `replaceBackend` re-guards on `backend.snapshot.busy`; if the inner guard no-ops, the preference is still persisted and `@Published var connection` still shows the new transport. The picker is disabled while busy, so this needs a state divergence to reach.
- `docs/wifi.md` correctly discloses plain HTTP on the LAN. Worth noting that a device passing both `matchesService` ("DS-940" substring) and `matchesCapabilities` (`MakeAndModel` substring) is trusted to supply page bytes, and the UI message at `ESCLScannerBackend.swift:114` does not name the host actually connected to.

### Coverage and limitations

Read-only review of the full diff surface: `ESCLScannerBackend.swift`, `ScannerDiscovery.swift`, `ESCLScannerProfile.swift`, `DS940Profile.swift`, `ESCLClient.swift`, `ScannerBackend.swift`, `ScannerCatalog.swift`, `AppModel.swift`, the `ContentView.swift` connection/scan controls, `App.swift` connect path, `DraftStore` capture lifecycle, and the build/CI wiring. Single pass plus one verification pass on the concrete candidates.

I ran nothing — no build, no tests, no device or network operations — so I am not certifying that this compiles, that the new `scanner-transport-tests` target links, or any hardware scenario. The Wi-Fi capture and jam-recovery evidence in `docs/validation.md` is claimed, not reproduced by me. The AI engine and filing worker were out of scope. Concurrency was reasoned about from the main-queue/`@MainActor` discipline in the code, not observed under load, so the narrow races I described as unreachable are argued rather than demonstrated.
