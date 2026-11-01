#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p test-results
cc -std=c11 -Wall -Wextra -Werror -ISources tests/theme_primitives.c -lm -o /tmp/wu-theme-primitives
/tmp/wu-theme-primitives | tee test-results/theme-primitives.txt
rm -f /tmp/wu-theme-primitives
if command -v xcrun >/dev/null 2>&1; then
  xcrun --sdk macosx clang -fobjc-arc -fobjc-arc-exceptions -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -ISources tests/theme_catalog.m Sources/ThemeArchive.m Sources/ThemeCatalog.m Sources/ThemeColors.m Sources/ThemeLibrary.m -framework Foundation -lz -o /tmp/wu-theme-catalog
  /tmp/wu-theme-catalog | tee test-results/theme-catalog.txt
  rm -f /tmp/wu-theme-catalog
  xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror -ISources tests/theme_archive.m Sources/ThemeArchive.m -framework Foundation -lz -o /tmp/wu-theme-archive
  /tmp/wu-theme-archive | tee test-results/theme-archive.txt
  rm -f /tmp/wu-theme-archive
else
  printf '%s\n' 'NOT RUN: Foundation/ZIP/file-transaction tests require macOS xcrun; UIKit XCTest requires an iOS test target.' | tee test-results/not-run.txt
fi
