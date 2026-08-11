#!/bin/bash
# Run the test suite. On a bare CommandLineTools install (no full Xcode) the
# swift-testing cross-import overlay needs explicit framework paths; full-Xcode
# environments (incl. CI) can run plain `swift test` instead.
set -euo pipefail
cd "$(dirname "$0")/.."

CLT_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

if [ -d "$CLT_FRAMEWORKS" ] && ! xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$CLT_FRAMEWORKS" \
    -Xlinker -F -Xlinker "$CLT_FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    "$@"
else
  exec swift test "$@"
fi
