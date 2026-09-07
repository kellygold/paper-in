#!/bin/bash
# Opt-in synthetic 300-dpi, 5/10/15-page benchmark. No scanner, provider or user scans.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
source scripts/toolchain.sh
source scripts/project.sh
xcrun swiftc "${paper_swift[@]}" "${paper_application[@]}" tests/app/Performance/main.swift -o .build/performance-tests
.build/performance-tests --demo
