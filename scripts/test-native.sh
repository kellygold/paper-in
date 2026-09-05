#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
source scripts/project.sh

# Each native executable is independent, making failures easy to locate.
xcrun swiftc "${paper_swift[@]}" "${paper_documents[@]}" tests/app/Documents/main.swift -o .build/store-tests
.build/store-tests

xcrun swiftc "${paper_swift[@]}" "${paper_documents[@]}" app/support/Diagnostics.swift tests/app/Connection/LegacyScanner.swift tests/app/Connection/main.swift -o .build/connection-tests
.build/connection-tests

xcrun swiftc -parse-as-library "${paper_swift[@]}" "${paper_documents[@]}" app/support/Diagnostics.swift app/scanning/ScannerBackend.swift app/scanning/DS940Profile.swift app/scanning/ESCLScannerProfile.swift app/scanning/ESCLClient.swift tests/app/ESCL/main.swift -o .build/escl-tests
.build/escl-tests

xcrun swiftc -parse-as-library "${paper_swift[@]}" app/support/*.swift app/scanning/*.swift tests/app/ScannerTransport/main.swift -o .build/scanner-transport-tests
.build/scanner-transport-tests

xcrun swiftc "${paper_swift[@]}" "${paper_documents[@]}" tests/app/Crop/main.swift -o .build/crop-tests
.build/crop-tests

xcrun swiftc "${paper_swift[@]}" "${paper_documents[@]}" tests/app/BlankPages/main.swift -o .build/blank-page-tests
.build/blank-page-tests

xcrun swiftc "${paper_swift[@]}" "${paper_documents[@]}" app/support/Diagnostics.swift app/scanning/ScannerBackend.swift tests/app/ScannerContract/main.swift -o .build/scanner-contract-tests
.build/scanner-contract-tests

xcrun swiftc "${paper_swift[@]}" "${paper_application[@]}" tests/app/AppFlow/main.swift -o .build/app-flow-tests
.build/app-flow-tests --demo
