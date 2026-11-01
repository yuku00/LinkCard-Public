#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p test-results
python3 tests/test_message_entries.py
if command -v xcrun >/dev/null 2>&1; then
  EXE=$(mktemp -t wu-message-entry-tests)
  trap 'rm -f "$EXE"' EXIT
  xcrun --sdk macosx clang -fobjc-arc -fobjc-arc-exceptions -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -ISources tests/message_entry_logic.m Sources/LinkLogic.m Sources/GroupLogic.m Sources/HomeLogic.m -framework Foundation -o "$EXE"
  "$EXE" > test-results/message-entry-logic.txt
  cat test-results/message-entry-logic.txt
else
  printf '%s\n' 'NOT RUN: production Foundation link/XML/config tests require macOS xcrun; UIKit/Safari/Files paths require unified iOS CI and device acceptance.' > test-results/message-entry-logic.txt
  cat test-results/message-entry-logic.txt
fi
