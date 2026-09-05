# Paper In — original prototype scope

Status: historical. Current behavior is documented in [the README](../../README.md) and [architecture](../architecture.md).

Scoped 5 September 2026. Target: Kelly's Brother DS-940DW over USB on macOS. This is the build specification. Implementation has started; see README.md for tested behavior and outstanding hardware checks. No scanner connection or settings were accessed during this scoping work.

The problem: a connection failure while adding pages interrupts scanning and makes it difficult to finish a document. The replacement should remember the scanner, capture successive sheets with very little interaction, and preserve every completed page even when scanning fails.

## Everyday experience

Open once, choose the output folder once, and leave the app available in the menu bar. The normal flow is:

1. Insert a sheet and press the scanner's physical Start button, if the hardware feasibility test succeeds. A large onscreen Scan button and Space key provide the same action.
2. Each completed side appears as a thumbnail with an explicit saved indicator. Insert the next sheet and scan again to append to this document.
3. Press **Save PDF** to publish one PDF into `~/Documents/Scanned Documents`. The app is ready for the next document immediately.

There is no save dialog on every scan. A document gets a unique default name; renaming is optional. Do not infer document boundaries from pauses: someone may spend several minutes finding the next page. Saving is the one deliberate action between documents.

The app can stay in the menu bar with its window closed. Scanning while the app is entirely quit is not promised. Offer launch at login as an explicit preference after the basic workflow works.

## Small first version

| Control or feature | Behavior |
| --- | --- |
| Scanner status | Remember this scanner; show Ready, Scanning, Waiting for paper, Disconnected, Busy or an actionable error. Never require selecting the same machine after every successful reconnect. |
| Scan / Space | Capture another sheet into the current document. Disable duplicate requests while scanning. |
| Save PDF | Publish a complete PDF and start a fresh document. Disable while capture is unsettled. |
| Page strip and preview | Reorder, rotate, undo removal and replace a selected bad page. Retain original page data. |
| One side / Both sides | Explicit per-document choice; preserve front/back order and both images. |
| Paper preset | Normal paper, card and long receipt, enabled only when verified against the selected backend's capabilities. Remember settings per preset. |
| Destination | Choose once; default to the existing scan folder. |
| Recent documents | Reopen an unfinished draft after restart; reveal finished PDFs in Finder. |

Default proposal: 300 dpi, colour, normal paper, single-sided. Both-sides scanning is one visible toggle. Do not silently discard blank backs. Show page count separately from sheets fed.

Errors should preserve context: **“Scanner disconnected. 6 pages saved. Reconnect to continue.”** An empty feeder between sheets is a normal waiting state. If feeder status is unavailable, say so instead of asserting that no paper is present.

An optional **scan when paper is inserted** mode is a later addition, conditional on reliable paper-presence events. It must be explicitly armed, visibly active and easy to pause; it must require a fresh insertion transition after each scan. Physical Start is the preferred hands-off trigger for the first version.

## What is established, and what is not

Brother documents Apple Image Capture and AirPrint scanning, including USB, for this model family and the DS-940DW respectively. Replacing iPrint&Scan does not require firmware source code. [Brother manual, printed pages 53–59](https://support.brother.com/g/s/id/htmldoc/ads/cv_ds640/uke/PDF/PDF.pdf)

Earlier in this session, macOS enumerated the DS-940DW through ImageCaptureCore, and its USB-backed local eSCL endpoint returned an Idle / ScannerAdfLoaded status. That is evidence of discovery and a status response, not proof of successful direct capture, long-paper support or reliable reconnects. The connection failure's root cause is still unknown.

Apple exposes scan completion and per-file delivery callbacks, allowing the app to save completed page files as they arrive. [ICScannerDeviceDelegate](https://developer.apple.com/documentation/imagecapturecore/icscannerdevicedelegate)

Apple also documents a browser callback for device button events when the application is the button's target. Its discussion refers to a device-delegate button callback during an open session. This does **not** prove the DS-940DW delivers the event through its current macOS driver. [Button-event documentation](https://developer.apple.com/documentation/imagecapturecore/icdevicebrowserdelegate/devicebrowser(_:requestsselect:))

Local SDK inspection adds a reason to test rather than promise: the macOS 26.2 headers declare `requestsSelectDevice:` and reference `didReceiveButtonPress:` in its discussion, but the latter was not found in `ICDevice.h`. Do not base the product on an assumed working legacy callback.

The SDK's `documentLoaded` documentation explicitly makes updates conditional on scanner-module support. Auto-feed behavior alone is not proof that reliable insertion events are exposed to software. [Apple property documentation](https://developer.apple.com/documentation/imagecapturecore/icscannerfunctionalunitdocumentfeeder/documentloaded)

## First milestone: prove the scanner path

Timebox an initial feasibility session before substantial UI work. Use ordinary test paper, with other scanning clients closed and Kelly available for physical feeding/button presses. Those hardware tests were not performed during scoping.

1. Discover the scanner and record its stable identity, available functional units, dimensions, resolutions, colour modes and duplex support. Verify whether a stable serial/UUID is exposed; don't use a temporary USB address or local HTTP port as identity.
2. Capture a single side, then both sides, to independent page files using ImageCaptureCore. Check actual image completeness and side order.
3. Test physical Start with the app foregrounded, backgrounded and with/without an open session. Determine how the app becomes the button target and record any configuration change needed before applying it.
4. Scan several sheets into one draft, unplug between sheets, reconnect and append again without losing pages or selecting the scanner again. Test a forced app exit separately.
5. Check long-receipt capabilities and a real receipt separately. Use only a supported combination of length, sides and resolution; preserve a partial failure as incomplete, never as a successful whole receipt.
6. If ImageCaptureCore fails repeatedly, evaluate direct eSCL sequentially as a replacement backend. Do not run two scanner clients or status pollers concurrently during a job. Verify capture, job completion and cancellation, not just status requests.

Record separate results for acquisition, reconnect, physical button, duplex and long paper. If the physical button is unavailable, report that clearly: the Space/Scan workflow can still ship, but it does not fulfill the full hardware-button experience.

A new app cannot repair insufficient USB power, a bad cable, a paper sensor or a firmware fault. Controlled comparisons are needed to locate the problem; don't promise that replacing the interface eliminates every connection error.

## Implementation recommendation

Native SwiftUI window and menu bar, with PDFKit for previews/export and ImageCaptureCore as the first scanner backend. This gives direct access to the supported Mac interfaces with a small application. Initial distribution is a local Mac app for Kelly.

Use a narrow scanner adapter so a direct eSCL backend can replace acquisition if testing warrants it. Avoid implementing both backends up front. eSCL is a standard HTTP scanning protocol, supported by existing scanning libraries, but receipt options and physical button support still need model-specific validation. [NAPS2 SDK](https://www.naps2.com/sdk/doc/api/)

NAPS2 is a useful baseline for checking the same hardware with a second implementation; its SDK or CLI is a fallback if native acquisition proves impractical. It supports Apple and eSCL backends and scripted scanning. Evaluate packaging and licence obligations before embedding or redistributing it. [Mac support](https://www.naps2.com/mac-scanning), [CLI](https://www.naps2.com/doc/command-line)

One scanner coordinator serializes acquisition requests and owns session opening/closing. It suppresses repeated clicks/button events, closes sessions on pause/quit and reports another client's ownership instead of resetting system services. It may reconnect the transport automatically, but must not blindly repeat a capture request after a timeout: the sheet may already have passed through.

The scan adapter emits capabilities, status, completed-page and failure events. The draft store owns page files and order. The UI reads the draft store. PDF export operates on saved pages and does not hold the scanner connection.

## Durability and folder integration

- Store active drafts under the app's Application Support directory, outside the folder being organized.
- Each side gets a unique page ID and a complete received image. Write to a temporary file, validate it, durably save it, then commit the draft manifest atomically. Only then show **Saved**.
- Keep page order, source sheet/job identifiers, side information where supplied, rotations, removals and unfinished acquisition state in the manifest. Reconcile orphaned page files after a crash.
- Every complete page received can survive app failure. An image still in transit at disconnection may require rescanning; preserve partial data for recovery but never count it as complete.
- Rescanning a selected page replaces it explicitly while keeping the old source recoverable. Do not deduplicate pages solely by visual similarity: genuinely repeated pages may be intentional.
- Finish exports a PDF into a temporary non-PDF file in the destination directory, validates page count/readability and atomically publishes it under a collision-safe unique filename. If export or folder access fails, the draft stays intact.
- The organizer sees only finished PDFs. It can move them immediately; subsequent scanning must not append to or recreate a previously published path. Later edits publish an explicit revision with a new identity.
- Preserve the draft until successful export is recorded; retain recovery copies in the initial version. Provide manual cleanup later with clear storage accounting.
- All capture, storage and export are local. OCR and classification operate after saving, independently of scanner ownership.

## Reliability acceptance tests

The release target is a complete evening's mixed-paper workflow without losing already-saved pages:

- Scan at least 30 sheets across multiple documents, including duplex sheets and cards; verify counts, readable images and correct order.
- Accumulate a ten-page document; unplug after a completed page; reconnect and finish the same draft.
- Force-quit after saved pages, during a transfer and during export. Reopen with every committed page restored and incomplete work clearly marked.
- Press Scan/Start repeatedly while busy. No parallel jobs, duplicate queued captures or accidental document completion.
- Verify no-paper, busy, jam and transport-error handling preserves the draft and gives the appropriate next action.
- Simulate disk-full, output-folder permission loss and filename collisions. Do not report saved/exported when persistence failed.
- Let the organizer move a finished PDF; scan a new document without modifying or recreating the previous PDF.
- Test reconnect and sleep/wake without duplicate subscriptions or jobs; reacquire only the selected scanner.
- Verify the physical button in the background if supported; test long receipts against actual negotiated limits. Mark either feature unavailable if its test fails.

Automated tests should exercise draft commits, crash recovery, event ordering and export using a fake scanner. Physical scanning and button routing require the real device; passing fake-device tests does not establish hardware compatibility.

## Build sequence and rough effort

| Stage | Deliverable | Planning estimate |
| --- | --- | --- |
| Feasibility and toolchain | Actual captures, button/reconnect findings, chosen backend | Half to one working day initially |
| Capture and durable drafts | Scan, append, recover, finish PDF with a basic window | One to two working days |
| Everyday controls | Thumbnails, rotate/reorder/remove, presets, menu bar and remembered destination | One to two working days |
| Fault testing and packaging | Mixed-paper session, failure tests, installable local app | One to two working days |

Approximately four to seven working days for a tested personal utility if the standard interface behaves. This is an engineering estimate, not a guaranteed completion date. A rough scanning prototype should precede that; undocumented button behavior or driver faults may extend the work and should trigger a scope decision rather than open-ended reverse engineering.

The current machine has Command Line Tools selected and a macOS 26.2 SDK. A prior Swift helper encountered a compiler/SDK mismatch; an Objective-C ImageCaptureCore helper compiled successfully. Verify a matching Swift toolchain at the start; do not silently upgrade developer tools or change the global selected developer directory.

Keep the first build focused on acquisition and document assembly. Searchable OCR, automatic categorization, accounts/cloud sync, editing existing external PDFs, broad scanner compatibility and firmware tooling are later or separate work. The existing organizer can continue classifying completed PDFs once scanning is stable.
