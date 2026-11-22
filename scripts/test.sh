#!/bin/sh
# Runs the test suite. Works with full Xcode or with just the Command Line Tools
# (which ship Swift Testing but neither put it on the default search path nor
# include the module for its Foundation overlay).
set -e
cd "$(dirname "$0")/.."
FLAGS=""
CLT=/Library/Developer/CommandLineTools/Library/Developer
if [ "$(uname)" = Darwin ] && ! xcode-select -p 2>/dev/null | grep -q Xcode.app && [ -d "$CLT/Frameworks/Testing.framework" ]; then
  FLAGS="-Xswiftc -F$CLT/Frameworks -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xlinker -F$CLT/Frameworks -Xlinker -rpath -Xlinker $CLT/Frameworks -Xlinker -rpath -Xlinker $CLT/usr/lib"
fi
# shellcheck disable=SC2086
exec swift test $FLAGS "$@"
