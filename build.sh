#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
source scripts/toolchain.sh
if [[ ! -d Worker/node_modules ]]; then
    echo 'Installing pinned AI worker dependencies locally…'
    (cd Worker && npm ci --ignore-scripts)
fi
paper_app="$PWD/.build/Paper In.app"
mkdir -p "$paper_app/Contents/MacOS" "$paper_app/Contents/Resources"
xcrun swiftc "${paper_swift[@]}" Sources/App.swift Sources/Scanning/*.swift Sources/Imaging/*.swift Sources/Storage/*.swift Sources/Support/*.swift Sources/UI/*.swift Sources/Preview/*.swift Sources/Filing/*.swift -o "$paper_app/Contents/MacOS/PaperIn"
xcrun clang -fobjc-arc -isysroot "$paper_sdk" -mmacosx-version-min=14.0 -arch "$paper_arch" Helpers/ocr.m -framework Foundation -framework AppKit -framework PDFKit -framework Vision -o "$paper_app/Contents/Resources/PaperOCR"
rsync -a --delete --exclude test Worker/ "$paper_app/Contents/Resources/Worker/"
cp Info.plist "$paper_app/Contents/Info.plist"
codesign --force --deep --sign - "$paper_app"
echo "Built $paper_app"
