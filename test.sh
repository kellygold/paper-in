#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# build.sh also prepares the local compiler overlay.
./build.sh
xcrun swiftc -swift-version 5 -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk \
  -target arm64-apple-macosx14.0 -vfsoverlay "$PWD/.build/compiler-overlay.json" \
  -module-cache-path "$PWD/.build/module-cache" \
  Sources/AutoCrop.swift Sources/DraftStore.swift Tests/main.swift -o .build/store-tests
.build/store-tests

xcrun swiftc -swift-version 5 -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk \
  -target arm64-apple-macosx14.0 -vfsoverlay "$PWD/.build/compiler-overlay.json" \
  -module-cache-path "$PWD/.build/module-cache" \
  Sources/AutoCrop.swift Sources/DraftStore.swift Sources/Diagnostics.swift Sources/Scanner.swift Tests/Connection/main.swift -o .build/connection-tests
.build/connection-tests

xcrun swiftc -parse-as-library -swift-version 5 -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk \
  -target arm64-apple-macosx14.0 -vfsoverlay "$PWD/.build/compiler-overlay.json" \
  -module-cache-path "$PWD/.build/module-cache" \
  Sources/ESCL.swift Sources/AutoCrop.swift Sources/DraftStore.swift Sources/Diagnostics.swift Tests/ESCL/main.swift -o .build/escl-tests
.build/escl-tests

xcrun swiftc -swift-version 5 -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk \
  -target arm64-apple-macosx14.0 -vfsoverlay "$PWD/.build/compiler-overlay.json" \
  -module-cache-path "$PWD/.build/module-cache" \
  Sources/AutoCrop.swift Sources/DraftStore.swift Tests/Crop/main.swift -o .build/crop-tests
.build/crop-tests
