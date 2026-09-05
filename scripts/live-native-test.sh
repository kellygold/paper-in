#!/bin/bash
# Opt-in: generated invoice -> native controller -> bundled worker -> Codex -> Undo.
# Uses the existing Codex login, consumes quota, and briefly tests a synthetic Keychain entry.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh
source scripts/toolchain.sh
source scripts/project.sh
xcrun swiftc "${paper_swift[@]}" "${paper_documents[@]}" tests/app/Integration/main.swift -o .build/integration-fixture
paper_fixture="$PWD/.build/live-native-$(uuidgen)"
.build/integration-fixture "$paper_fixture" codex
# Compile the harness into its own app so Bundle.main resolves the packaged resources.
paper_harness="$paper_fixture/Harness.app"
ditto '.build/Paper In.app' "$paper_harness"
xcrun swiftc "${paper_swift[@]}" app/support/PaperError.swift app/filing/*.swift tests/app/ControllerIntegration/main.swift -o "$paper_harness/Contents/MacOS/PaperIn"
codesign --force --deep --sign - "$paper_harness"
"$paper_harness/Contents/MacOS/PaperIn" "$paper_fixture"
echo "Synthetic evidence retained in $paper_fixture"
