# DMG and website

## Build a download

On an Apple Silicon Mac with the normal [development prerequisites](development.md):

```sh
./test.sh
./scripts/package-dmg.sh
```

The script rebuilds the app, bundles the checksum-pinned official Node 22.23.2 runtime, preserves dependency licenses and vendor binaries, and creates `.build/dist/Paper-In-0.4.0-arm64.dmg` plus a SHA-256 sidecar. The disk image contains Paper In, an Applications shortcut, and offline opening instructions. It does not update an installed copy or touch drafts.

The current script produces an **ad-hoc signed, unnotarized beta**. It does not use a Developer ID certificate. Do not describe this artifact as notarized. Apple Silicon and macOS 14+ are required; Intel packaging is not validated.

For a notarized release, the maintainer needs an active Apple Developer Program membership, a Developer ID Application identity and notarization credentials stored outside the repository. Sign our executables with hardened runtime and a secure timestamp, preserve each vendor's redistribution/signing requirements, submit using Apple's notarization tools, and staple the accepted ticket. Validate the final downloaded DMG with Gatekeeper on a clean Mac before changing the website's installation instructions. Merely having a paid membership does not sign a build.

See [Apple's signing guidance](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) and [third-party notices](third-party.md).

## Static website

`site/` is plain HTML, CSS and local images. There is no build step, application server, analytics or third-party font request.

```sh
python3 -m http.server 8766 --bind 127.0.0.1 --directory site
```

Open `http://127.0.0.1:8766`. Check desktop and narrow mobile widths, the setup page, keyboard navigation and download links. The setup page is self-contained because the DMG also includes it offline.

GitHub Pages uses `.github/workflows/pages.yml`; only `site/` is uploaded. Select **GitHub Actions** as the Pages build source in repository settings. Changes on `main` publish to `https://kellygold.github.io/paper-in/`. Release binaries belong in GitHub Releases, not the Pages artifact.

## Release order

1. Update the app version, release notes and matching links in `site/`. Run the full tests and independent review.
2. Build the DMG from the reviewed source revision. Mount it read-only, copy the app to a temporary directory, verify signatures and runtime versions, launch demo mode and exercise synthetic PDF/filing paths. Never use personal scans as public evidence.
3. Publish the matching GitHub release with its DMG and checksum before deploying a website that links to it. Label signing status, architecture and known hardware limitations honestly.
4. Merge the website update, verify the Pages workflow, follow the live download link and check the downloaded checksum.

Never commit signing keys, notarization credentials, `.build`, app bundles or personal scan data. Keep the source and the published binary tied to the same commit.
