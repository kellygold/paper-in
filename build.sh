#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
source scripts/toolchain.sh
source scripts/project.sh
if ! command -v node >/dev/null || ! command -v npm >/dev/null; then
    echo 'Building Paper In requires Node.js 22+ and npm. See README.md.' >&2
    exit 1
fi
node -e 'if (Number(process.versions.node.split(".")[0]) < 22) { console.error("Node.js 22 or later is required."); process.exit(1); }'
# Refresh dependencies when the lockfile changes; never silently build stale SDKs.
if [[ ! -d ai/node_modules ]] || ! cmp -s ai/package-lock.json ai/node_modules/.paper-in-lock; then
    (cd ai && npm ci --ignore-scripts)
    cp ai/package-lock.json ai/node_modules/.paper-in-lock
fi
paper_app="$PWD/.build/Paper In.app"
mkdir -p "$paper_app/Contents/MacOS" "$paper_app/Contents/Resources"
xcrun swiftc "${paper_swift[@]}" app/App.swift "${paper_application[@]}" -o "$paper_app/Contents/MacOS/PaperIn"
xcrun clang -fobjc-arc -isysroot "$paper_sdk" -mmacosx-version-min=14.0 -arch "$paper_arch" ai/ocr.m -framework Foundation -framework AppKit -framework PDFKit -framework Vision -o "$paper_app/Contents/Resources/PaperOCR"
# Worker is a stable installed-resource name; source code lives in ai/.
rsync -a --delete --exclude ocr.m --exclude README.md ai/ "$paper_app/Contents/Resources/Worker/"
cp app/Info.plist "$paper_app/Contents/Info.plist"
codesign --force --deep --sign - "$paper_app"
echo "Built $paper_app"
