#!/bin/bash
# Opt-in. Sends fictional invoice text through the selected provider.
set -euo pipefail
cd "$(dirname "$0")/.."
paper_provider="${1:-codex}"
case "$paper_provider" in
  codex|claudeSDK) ;;
  openaiAPI) : "${OPENAI_API_KEY:?Set an API key for this opt-in live test}"; : "${PAPER_IN_TEST_MODEL:?Set the API model}" ;;
  anthropicAPI) : "${ANTHROPIC_API_KEY:?Set an API key for this opt-in live test}"; : "${PAPER_IN_TEST_MODEL:?Set the API model}" ;;
  *) echo 'Choose codex, claudeSDK, openaiAPI or anthropicAPI.'; exit 2 ;;
esac
./build.sh
source scripts/toolchain.sh
source scripts/project.sh
xcrun swiftc "${paper_swift[@]}" "${paper_documents[@]}" tests/app/Integration/main.swift -o .build/integration-fixture
paper_fixture="$PWD/.build/live-$(uuidgen)"
.build/integration-fixture "$paper_fixture" "$paper_provider"
node tests/ai/end-to-end.mjs "$paper_fixture"
echo "Synthetic evidence retained in $paper_fixture"
