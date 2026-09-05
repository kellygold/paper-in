#!/bin/bash
# Source from build/test scripts. No system toolchain settings are changed.
paper_sdk="${PAPER_IN_SDK:-$(xcrun --show-sdk-path)}"
paper_arch="${PAPER_IN_ARCH:-$(uname -m)}"
paper_overlay=()
# This CLT release ships a newer selected SDK than its Swift compiler supports.
paper_swift_version="$(swift --version 2>&1)"
if [[ -z "${PAPER_IN_SDK:-}" && "$paper_swift_version" == *"Swift version 6.1.2"* && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk ]]; then
    paper_sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk
    python3 - <<'PY'
from pathlib import Path
import json
p=Path('.build').resolve(); p.mkdir(exist_ok=True)
(p/'empty.modulemap').write_text('')
(p/'compiler-overlay.json').write_text(json.dumps({'version':0,'roots':[{'type':'file','name':'/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap','external-contents':str(p/'empty.modulemap')}]}))
PY
    paper_overlay=(-vfsoverlay "$PWD/.build/compiler-overlay.json")
fi
paper_swift=(-swift-version 5 -sdk "$paper_sdk" -target "$paper_arch-apple-macosx14.0" "${paper_overlay[@]}" -module-cache-path "$PWD/.build/module-cache")
