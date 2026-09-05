#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk
# Local Clang VFS overlay avoids duplicate SwiftBridging module maps in this CLT install.
# No system files or global toolchain selections are changed.
python3 - <<'PY'
from pathlib import Path
import json
p=Path('.build').resolve()
(p/'empty.modulemap').write_text('')
(p/'compiler-overlay.json').write_text(json.dumps({'version':0,'roots':[{'type':'file','name':'/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap','external-contents':str(p/'empty.modulemap')}]}))
PY
APP="$PWD/.build/Paper In.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -swift-version 5 -sdk "$SDK" -target arm64-apple-macosx14.0 \
  -vfsoverlay "$PWD/.build/compiler-overlay.json" -module-cache-path "$PWD/.build/module-cache" \
  Sources/ESCL.swift Sources/AutoCrop.swift Sources/DraftStore.swift Sources/Diagnostics.swift Sources/App.swift \
  -o "$APP/Contents/MacOS/PaperIn"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
