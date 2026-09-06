#!/bin/bash
# Opt-in: generated invoice -> native controller -> bundled worker -> Codex -> Undo.
# Uses the existing Codex login, consumes quota, and briefly tests a synthetic Keychain entry.
set -euo pipefail
cd "$(dirname "$0")/.."
# Optionally validate resources copied from a mounted DMG, without rebuilding it.
if [[ -z "${PAPER_IN_TEST_APP:-}" ]]; then ./build.sh; fi
paper_test_app="${PAPER_IN_TEST_APP:-$PWD/.build/Paper In.app}"
[[ -d "$paper_test_app/Contents/Resources/Worker" ]] || { echo 'Test app resources are missing.' >&2; exit 1; }
source scripts/toolchain.sh
source scripts/project.sh
xcrun swiftc "${paper_swift[@]}" "${paper_documents[@]}" tests/app/Integration/main.swift -o .build/integration-fixture
paper_fixture="$PWD/.build/live-native-$(uuidgen)"
.build/integration-fixture "$paper_fixture" codex
# Compile the harness into its own app so Bundle.main resolves the packaged resources.
paper_harness="$paper_fixture/Harness.app"
ditto "$paper_test_app" "$paper_harness"
xcrun swiftc "${paper_swift[@]}" app/support/PaperError.swift app/filing/*.swift tests/app/ControllerIntegration/main.swift -o "$paper_harness/Contents/MacOS/PaperIn"
codesign --force --sign - "$paper_harness"
"$paper_harness/Contents/MacOS/PaperIn" "$paper_fixture"
echo "Synthetic evidence retained in $paper_fixture"
