#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# build.sh also prepares the local compiler overlay.
./build.sh
source scripts/toolchain.sh
xcrun swiftc "${paper_swift[@]}" \
  Sources/Support/PaperError.swift Sources/Filing/FilingTypes.swift Sources/Preview/SheetGroup.swift Sources/Imaging/AutoCrop.swift Sources/Storage/DraftStore.swift Tests/main.swift -o .build/store-tests
.build/store-tests

xcrun swiftc "${paper_swift[@]}" \
  Sources/Support/PaperError.swift Sources/Filing/FilingTypes.swift Sources/Preview/SheetGroup.swift Sources/Imaging/AutoCrop.swift Sources/Storage/DraftStore.swift Sources/Support/Diagnostics.swift Tests/Connection/LegacyScanner.swift Tests/Connection/main.swift -o .build/connection-tests
.build/connection-tests

xcrun swiftc -parse-as-library "${paper_swift[@]}" \
  Sources/Scanning/ESCLClient.swift Sources/Scanning/DS940Profile.swift Sources/Scanning/ScannerBackend.swift Sources/Support/PaperError.swift Sources/Filing/FilingTypes.swift Sources/Preview/SheetGroup.swift Sources/Imaging/AutoCrop.swift Sources/Storage/DraftStore.swift Sources/Support/Diagnostics.swift Tests/ESCL/main.swift -o .build/escl-tests
.build/escl-tests

xcrun swiftc "${paper_swift[@]}" \
  Sources/Support/PaperError.swift Sources/Filing/FilingTypes.swift Sources/Preview/SheetGroup.swift Sources/Imaging/AutoCrop.swift Sources/Storage/DraftStore.swift Tests/Crop/main.swift -o .build/crop-tests
.build/crop-tests

(cd Worker && npm test)
xcrun swiftc "${paper_swift[@]}" Sources/Support/PaperError.swift Sources/Filing/FilingTypes.swift Sources/Imaging/AutoCrop.swift Sources/Storage/DraftStore.swift Sources/Support/Diagnostics.swift Sources/Scanning/ScannerBackend.swift Tests/ScannerContract/main.swift -o .build/scanner-contract-tests
.build/scanner-contract-tests
xcrun swiftc "${paper_swift[@]}" Sources/Support/*.swift Sources/Imaging/*.swift Sources/Storage/*.swift Sources/Filing/*.swift Sources/Scanning/*.swift Sources/Preview/*.swift Sources/UI/*.swift Tests/AppFlow/main.swift -o .build/app-flow-tests
.build/app-flow-tests --demo
