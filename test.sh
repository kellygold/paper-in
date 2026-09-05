#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# Tests use synthetic documents and fake devices; no scanner or AI account is used.
./build.sh
./scripts/test-native.sh
(cd ai && npm test)
