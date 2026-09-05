#!/bin/bash
# Create a Developer ID signed and notarized Apple Silicon disk image.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -m)" == arm64 && "${PAPER_IN_ARCH:-arm64}" == arm64 ]] || { echo 'This DMG target is Apple Silicon (arm64) only.' >&2; exit 1; }
: "${PAPER_IN_SIGN_IDENTITY:?Set PAPER_IN_SIGN_IDENTITY to your Developer ID Application identity. Use build.sh for local ad-hoc builds.}"
: "${PAPER_IN_NOTARY_PROFILE:?Set PAPER_IN_NOTARY_PROFILE to a notarytool Keychain profile.}"
./build.sh
paper_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' app/Info.plist)
paper_node_version=22.23.2
paper_node_hash=61130f394c1630d211dd50aecc4353d379480f36d3ac913cd85dbba1aed585c6
paper_archive="node-v${paper_node_version}-darwin-arm64.tar.gz"
mkdir -p .build/downloads .build/dist
paper_download="$PWD/.build/downloads/$paper_archive"
if [[ ! -f "$paper_download" ]]; then
  curl --fail --location --retry 3 "https://nodejs.org/dist/v${paper_node_version}/${paper_archive}" -o "$paper_download.partial"
  mv "$paper_download.partial" "$paper_download"
fi
[[ "$(shasum -a 256 "$paper_download" | cut -d ' ' -f1)" == "$paper_node_hash" ]] || { echo 'Node archive checksum mismatch.' >&2; exit 1; }
paper_stage=$(mktemp -d "$PWD/.build/dmg-stage.XXXXXX")
trap 'rm -rf "$paper_stage"' EXIT
mkdir -p "$paper_stage/node" "$paper_stage/volume"
tar -xzf "$paper_download" -C "$paper_stage/node" --strip-components=1
paper_app="$paper_stage/volume/Paper In.app"
ditto '.build/Paper In.app' "$paper_app"
mkdir -p "$paper_app/Contents/Resources/Runtime/bin" "$paper_app/Contents/Resources/Notices"
cp "$paper_stage/node/bin/node" "$paper_app/Contents/Resources/Runtime/bin/node"
cp "$paper_stage/node/LICENSE" "$paper_app/Contents/Resources/Runtime/LICENSE"
cp LICENSE "$paper_app/Contents/Resources/Notices/Paper-In-MIT.txt"
cp docs/third-party.md "$paper_app/Contents/Resources/Notices/Third-party.md"
cp docs/notices/*.txt "$paper_app/Contents/Resources/Notices/"
# Sign our helper and app with hardened runtime. Preserve vendor signatures.
codesign --force --sign "$PAPER_IN_SIGN_IDENTITY" --options runtime --timestamp "$paper_app/Contents/Resources/PaperOCR"
codesign --force --sign "$PAPER_IN_SIGN_IDENTITY" --options runtime --timestamp "$paper_app"
codesign --verify --deep --strict "$paper_app"
[[ "$("$paper_app/Contents/Resources/Runtime/bin/node" --version)" == "v${paper_node_version}" ]]
ln -s /Applications "$paper_stage/volume/Applications"
cp site/install.html "$paper_stage/volume/Start Here.html"
paper_dmg="$PWD/.build/dist/Paper-In-${paper_version}-arm64.dmg"
paper_candidate="$PWD/.build/dist/Paper-In-${paper_version}-arm64.unnotarized.dmg"
paper_receipt="$PWD/.build/dist/Paper-In-${paper_version}-arm64.notary.json"
hdiutil create -quiet -ov -volname 'Paper In' -srcfolder "$paper_stage/volume" -fs HFS+ -format UDZO "$paper_candidate"
codesign --force --sign "$PAPER_IN_SIGN_IDENTITY" --timestamp "$paper_candidate"
hdiutil verify "$paper_candidate"
# Keep an unaccepted candidate under a distinct name, never the release filename.
# A timeout leaves the submitted file and receipt available for inspection/resume.
xcrun notarytool submit "$paper_candidate" --keychain-profile "$PAPER_IN_NOTARY_PROFILE" --wait --timeout 30m --output-format json > "$paper_receipt"
/usr/bin/plutil -extract status raw -o - "$paper_receipt" | /usr/bin/grep -qx Accepted
xcrun stapler staple "$paper_candidate"
xcrun stapler validate "$paper_candidate"
codesign --verify --strict "$paper_candidate"
spctl --assess --type open --context context:primary-signature "$paper_candidate"
mv "$paper_candidate" "$paper_dmg"
(cd .build/dist && shasum -a 256 "$(basename "$paper_dmg")" > "$(basename "$paper_dmg").sha256")
echo "Packaged $paper_dmg (Developer ID signed, notarized and stapled)"
