# DMG and website

## Build a download

On an Apple Silicon Mac with the normal [development prerequisites](development.md):

```sh
./test.sh
PAPER_IN_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
PAPER_IN_NOTARY_PROFILE="paper-in" ./scripts/package-dmg.sh
```

The script rebuilds the app, bundles the checksum-pinned official Node 22.23.2 runtime, preserves dependency licenses and vendor binaries, and creates `.build/dist/Paper-In-0.4.0-arm64.dmg` plus a SHA-256 sidecar. The disk image contains Paper In, an Applications shortcut, and offline opening instructions. It does not update an installed copy or touch drafts.

The release script requires a Developer ID Application identity and a validated `notarytool` Keychain profile. It signs Paper In and its OCR helper with hardened runtime and a secure timestamp, preserving vendor signatures. It submits the app first, requires Accepted status, staples its ticket and checks distribution policy. It then signs and notarizes the DMG, staples and validates its ticket, and checks Gatekeeper before placing it at the release filename. The app therefore retains its own stapled ticket when copied into Applications. Apple Silicon and macOS 14+ are required; Intel packaging is not validated.

Set up the profile interactively with `xcrun notarytool store-credentials paper-in`. Credentials and signing keys stay in Keychain, never in the repository. The script retains the current `.app.unnotarized.zip` or `.unnotarized.dmg` and JSON receipt if a submission fails or exceeds its 30-minute wait; these files must not be published. Use the submission ID with `notarytool info`, `wait` or `log` to investigate without resubmitting. A local developer build via `./build.sh` remains ad-hoc signed and does not need Apple membership.

The maintainer needs an active Apple Developer Program membership. Validate the final downloaded DMG and copied app with Gatekeeper. A separate clean Mac is recommended for first-install testing; same-Mac checks do not establish the full clean-machine experience. Only publish the notarized installation instructions with an accepted, verified artifact.

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
