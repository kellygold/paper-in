# Troubleshooting

## A saved PDF has disappeared from the inbox

Open **Saved documents**, select it, and choose **Show PDF in Finder**. Successful AI filing gives it a descriptive name and moves it to its proposed folder. Undo is available there too.

## A PDF is still in the top-level folder

AI filing applies to new saves after it is enabled. It does not automatically queue earlier exports. Filename timestamps reflect when a draft was created, so they can differ from Finder's last-modified time.

## Organizing did not finish

Open **Saved documents** and inspect the status:

- **Needs review:** check the folder and filename, then approve it.
- **Needs attention:** read the error, correct login/model/key settings, then **Retry analysis**. Retry uses your current settings.
- **Waiting to organize:** use **Resume queue** with AI filing enabled.

The PDF remains saved if a provider fails. Weak OCR, a new folder, a potential duplicate, or disagreement between checks can require review even when automatic filing is enabled.

## AI filing cannot start

Check that Node.js 22+ is installed. The app can detect common Homebrew and nvm locations; an explicit executable path can be set in **AI filing → Runtime paths**. Check the selected provider's [login or API setup](providers.md). Scanning does not require AI to be available.

## Scanner cannot connect, reports no paper, or ends without an image

Confirm the DS-940DW's mode switch matches **USB** or **Wi-Fi** in Paper In, close other scanner applications, and inspect the scanner's fault indicators and paper path. For network setup and discovery, see [Wi-Fi setup](wifi.md). Use the manufacturer's instructions to resolve a reported jam. Then use the app's explicit connection retry. Do not assume a successful insertion movement means a complete scan was captured.

Completed pages already in the draft are retained. An image that never arrived may need rescanning. When reporting a bug, include the scanner model, macOS/app version, exact action, error message, and a redacted connection log. Do not attach personal document images.

For a receipt longer than A4, choose **Paper → Long paper** before scanning. This requests up to 1.8 m at 300 dpi and scans one side at a time. Close the output guide so the receipt exits straight through; support the paper as it feeds. Return to **Standard (A4)** for ordinary duplex scans. Long paper is offered only when the connected scanner advertises the required simplex scan area.

Brother's [manual](https://support.brother.com/g/s/id/htmldoc/ads/cv_ds640/uke/PDF/PDF.pdf) lists 1,828.8 mm for single-sided scanning and excludes duplex from Long Paper mode. Our eSCL capability probe reported separate simplex and duplex limits; the app never applies the larger simplex area to a duplex request. A synthetic maximum-length receipt has offline coverage; physical long-paper scanning is still being validated.

Other models and physical scanner-button events are not supported yet.
