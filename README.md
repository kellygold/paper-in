# Paper In

**Put the paper in. Scan. Save.**

A small Mac app for turning a stack of paper into PDFs you can find again. Built after one too many “no paper,” “jam,” and “could not connect” messages from the scanner's original software.

Paper In currently supports the **Brother DS-940DW over USB**, with experimental Wi-Fi support. It is an independent community project, not a Brother product.

![Front and back of a sheet displayed together in Paper In. This screenshot uses generated sample pages.](docs/images/paired-preview.png)

## What it does

- **One document, as many pages as you need.** Scan a sheet, add another, save one PDF.
- **Front and back together.** Review each sheet, zoom either side, rotate, crop, or remove pages. Removed pages can be restored.
- **Recoverable drafts.** Completed pages are saved as you go, including across app restarts.
- **Skip blank pages.** Hide clearly blank fronts or backs, including single-sided scans, with restoration before saving.
- **Optional AI filing.** Read the saved document, suggest a name and folder, check related documents, and file clear matches. Uncertain results wait for review.
- **Originals and Undo.** AI filing keeps the original PDF. Existing files are not overwritten, and filing can be undone.

Scanning works without an AI account. AI filing is off by default.

See the [release notes](docs/releases.md) for the latest changes and validation limits.

## Download

[Get Paper In for Mac](https://kellygold.github.io/paper-in/) · [Releases and checksums](https://github.com/kellygold/paper-in/releases)

The 0.4.0 beta DMG is for Apple Silicon Macs running macOS 14 or later. Drag Paper In into Applications. Node and the provider runtimes are included. This beta is ad-hoc signed and **not notarized**; see the [opening instructions](https://kellygold.github.io/paper-in/install.html). Other Mac architectures and scanner models are not yet verified.

## Build from source

You need Apple's Xcode Command Line Tools (or Xcode), **Node.js 22+**, and npm. If the Apple tools are missing, run `xcode-select --install` first.

```sh
git clone https://github.com/kellygold/paper-in.git
cd paper-in
./build.sh
open '.build/Paper In.app'
```

The build installs pinned AI SDKs inside the project and signs the app for local use. It does not change your global CLI installations or replace an installed Paper In app. To install it, quit any running copy and copy `.build/Paper In.app` into your Applications folder.

Source builds include both provider runtimes but use your installed Node. DMGs also bundle Node. [Build details and development commands →](docs/development.md)

## Scan your first document

1. Put the DS-940DW in USB mode, connect it, and close other scanner apps.
2. Open Paper In, choose your destination by clicking the folder path at the bottom, then click **Connect**.
3. Insert a sheet and click **Scan** or press Space. Repeat to add sheets to the same document.
4. Review the pages and click **Save PDF** or press Command-S.

The destination is remembered. Saving starts a fresh document. The scanner's physical Start button is not supported yet; use the app button or Space.

Use **Options → Skip blank pages** to leave clearly blank pages out of the preview and PDF. It applies to either side and single-sided scans. It starts off and upgrades preserve the existing preference. Skipped pages retain their original image and can be restored before Save PDF, including when every page was blank. Existing drafts are not reclassified. Faint content, print-through and scanner noise can still require manual review.

**Move earlier** and **Move later** change the selected page's order in the exported PDF and switch to **Single page** so the resulting order is visible. In **Single page** view, each front and back has its own sidebar row; use the arrows above the preview to move between pages.

For Wi-Fi, first connect the scanner to the same local network as your Mac, select **Options → Connection → Wi-Fi** in Paper In, then **Connect**. The preview, draft, PDF and AI filing workflow stays the same. See [Wi-Fi setup](docs/wifi.md) for the phone-assisted setup that keeps your Mac online and the current validation limits.

To explore the UI without a scanner:

```sh
open -n '.build/Paper In.app' --args --demo
```

Demo mode uses generated pages, temporary storage, and no AI requests.

## Let AI organize the saved PDFs

Open **AI filing…**, enable filing, and choose a provider:

| Connection | Setup |
| --- | --- |
| Codex | Use the official runtime's existing login with `codex login`. |
| Claude | Use the official runtime's existing login with `claude auth login`. |
| OpenAI or Anthropic API | Enter a model ID and an API key. Keys are stored in macOS Keychain. API billing is separate. |

Existing-login integrations use the official SDKs. Availability depends on your provider's account, limits, and terms; see [provider setup and eligibility](docs/providers.md).

New saves go to `_Inbox` first. The worker extracts text locally, proposes a filename and folder, then makes a second AI call to check the proposal. You can keep scanning while it runs.

Open **Saved documents** to see progress, approve a suggestion, change its name or folder, retry, Undo, or **Show PDF in Finder**. New folders, weak OCR, possible duplicates, related documents, and disagreements between the two checks require review. Related files are never automatically merged.

Enabling AI does **not** retroactively organize PDFs saved before it was enabled. It applies to subsequent saves, including a draft started before enabling it.

**Privacy:** extracted text, folder names, and excerpts from up to eight candidate PDFs are sent to the selected provider. Page images stay local. This is text-based filing, so photographs without text will generally need manual organization. [Data storage, privacy, and recovery →](docs/privacy-and-recovery.md)

## Find your way around the code

There are two parts to the app: the Mac interface and the AI filing process. They share one document workflow.

```text
app/          Mac app: screens, scanner connections, documents, AI settings
ai/           AI filing: OCR, providers, naming, folders, review, Undo
tests/        Automated checks and opt-in synthetic integration tests
docs/         Architecture, provider setup, development, test evidence
scripts/      Build, test and DMG packaging helpers
site/         Static GitHub Pages website
build.sh      Build the app
test.sh       Build and run the automated checks
```

Start with [the project map](docs/project-map.md). It explains which file to open for common changes. The [architecture guide](docs/architecture.md) describes the shared contracts and how to add a scanner or AI provider.

A new model supported by an existing provider only needs a model ID in settings. A new provider or scanner gets an adapter; previews, storage, review, and recovery stay shared.

## Contribute

```sh
./test.sh
```

The default tests use synthetic documents and fake scanners/providers. No account, API key, or connected scanner is needed to run them. CI runs the same command on macOS. Live provider checks are separately opt-in.

See [contributing](docs/contributing.md) for a first change, [test evidence](docs/validation.md) for what is verified, and [troubleshooting](docs/troubleshooting.md) for scanner or filing problems.

## Current limits

- DS-940DW only. Wi-Fi is experimental; one physical duplex scan through the shared backend is verified. Other scanner models and multi-sheet feeders are not yet supported. See [validation](docs/validation.md) for the tested scope.
- Capture is 300 dpi, colour. **Auto** requests the scanner’s advertised automatic cropping within a 35.6 cm scan area and supports both sides when advertised. **A4** uses a fixed area; **Long receipt** allows up to 1.8 m, one side at a time. Close the output guide for straight-through feeding with long paper. Device Auto and long-paper behavior are still undergoing hardware validation. Deskew is not implemented.
- **Options → Skip blank pages** applies to either side, single-sided scans and explicit imports. Originals remain restorable before saving; an all-blank capture stays in the draft and does not create an empty PDF. Cleanup preferences carry over from earlier builds.
- OCR feeds AI filing; PDFs do not yet receive a searchable text layer.
- Very large exports may briefly pause the interface. Drafts and recovery copies are retained without automatic cleanup.
- AI can misread or misclassify documents. Its second check uses the same provider, and confidence is a heuristic. Review and Undo remain available.

## License

Paper In's original source is [MIT licensed](LICENSE). Dependencies keep their own licenses, including the proprietary Claude SDK/runtime. See [third-party notices](docs/third-party.md). The beta download preserves vendor runtimes and notices; Developer ID signing and notarization are pending. See [distribution](docs/distribution.md).
