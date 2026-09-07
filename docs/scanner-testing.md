# Testing another scanner

Only the Brother DS-940DW is currently supported. Owning another scanner and volunteering to test it is useful; maintainers do not need to buy every model. A model name or an eSCL capability response alone does not establish compatibility.

## Start with a report

Open the **Scanner compatibility / volunteer testing** issue template. Include the exact model, firmware if available, macOS version, connection type, feeder type and willingness to test a development build. Do not change the app's supported-model checks just to force a connection.

A maintainer can then choose a bounded discovery check for that model. Share only the requested capability/diagnostic excerpt. Remove serial numbers, network addresses, machine/user names and any document text. Never attach personal scans, passwords or authentication material. Generated test pages are enough.

## Hardware checklist

Work with an isolated test draft and fictional documents. Record the app revision, firmware and connection for each result. Mark unsupported or untested features explicitly; one USB result does not verify Wi-Fi.

- Connect, disconnect and reconnect; verify the actual model and advertised capabilities.
- Scan one printed front, then a distinct printed front/back pair if duplex is supported. Check order, completeness and physical PDF size.
- Add 5, 10 and 15 pages, navigate both sides, remove/restore and rotate pages. Before saving, reopen the app and verify the unfinished draft is recovered. Then save one PDF and check its page count, order and dimensions.
- Try a blank front and a blank back when the device supports them. Confirm faint real marks are retained, and skipped pages can be restored.
- Test only document types and lengths the manufacturer's instructions permit. Check both ends of receipts and crop boundaries.
- Start with an empty feeder and check the error. Observe recovery from a naturally occurring fault; do not deliberately jam or damage the scanner.
- Check cancellation, a connection loss, and sleep/wake during a synthetic test. Confirm received pages survive and the app never silently repeats an uncertain scan.
- For an automatic multi-sheet feeder or flatbed, record its separate behavior. Do not assume a one-sheet/two-image capture contract fits it.

A maintainer reviews the evidence and automated regressions before listing a model as supported. A partial result is recorded as experimental, with its exact limits.

## Implementing support

Read [architecture](architecture.md#adding-a-scanner). A compatible one-sheet eSCL model may reuse the shared discovery, transport, session and document components through a model profile. A different protocol implements the existing backend contract; the PDF and AI filing layers remain shared. New capabilities should be based on hardware evidence and covered by synthetic fixtures.
