#!/bin/sh
set -eu
TESTDIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$TESTDIR/../.." && pwd)
WORK=$(mktemp -d /tmp/wu-native-tests.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
cc -std=c11 -Wall -Wextra -Werror -I "$ROOT/Sources" "$TESTDIR/native_policy.c" -o "$WORK/policy"
"$WORK/policy"
cc -std=c11 -Wall -Wextra -Werror -I "$ROOT/Sources" "$TESTDIR/native_boot.c" "$ROOT/Sources/WUNativeBoot.c" -o "$WORK/boot"
"$WORK/boot"
MAIN=${WU_MAIN_SOURCE:-$ROOT}
python3 "$TESTDIR/extract_core.py" "$MAIN/Sources/Core.m" "$WORK/core_hooks.inc"
if command -v xcrun >/dev/null 2>&1; then
  xcrun --sdk macosx clang -std=c11 -Wall -Wextra -Werror -I "$ROOT/Sources" -c "$ROOT/Sources/WUNativeBoot.c" -o "$WORK/boot.o"
  build() {
    name=$1; shift
    xcrun --sdk macosx clang -fobjc-arc -fobjc-arc-exceptions -fblocks -Wall -Wextra -Werror -Wno-unused-parameter \
      -I "$TESTDIR" -I "$TESTDIR/stubs" -I "$MAIN/Sources" -I "$ROOT/Sources" -I "$WORK" -include "$TESTDIR/clock.h" "$@" \
      "$TESTDIR/UIKitMock.m" "$TESTDIR/TestHost.m" \
      "$ROOT/Sources/WUNative.m" "$ROOT/Sources/WUNativeEntries.m" "$ROOT/Sources/WUNativeAction.m" "$ROOT/Sources/WUNativeRecovery.m" \
      "$ROOT/Sources/WUNativeInteractions.m" "$ROOT/Sources/WUNativeGames.m" "$ROOT/Sources/WUNativeGameLogic.m" \
      "$ROOT/Sources/WUNativeSettings.m" "$MAIN/Sources/MessageConstruction.m" "$WORK/boot.o" \
      -framework Foundation -framework CoreGraphics -o "$WORK/$name"
  }
  build actions "$TESTDIR/native_interactions_games.m"
  "$WORK/actions"
  build actions_bad -DWU_TEST_BAD_ABI=1 "$TESTDIR/native_interactions_games.m"
  "$WORK/actions_bad" bad-abi
  build actions64 -DWU_TEST_64=1 "$TESTDIR/native_interactions_games.m"
  "$WORK/actions64"
  build actions64_bad -DWU_TEST_64=1 -DWU_TEST_BAD_ABI=1 "$TESTDIR/native_interactions_games.m"
  "$WORK/actions64_bad" bad-abi
  build hooks "$TESTDIR/native_hooks.m"; "$WORK/hooks"
  build entries "$ROOT/tests/native-gaps/native_entries.m"; "$WORK/entries"
  build entries_bad -DWU_TEST_ENTRY_BAD_ABI=1 "$ROOT/tests/native-gaps/native_entries.m"; "$WORK/entries_bad"
  build boundary -DWU_NATIVE_BOUNDARY_TEST=1 "$ROOT/tests/native-gaps/native_boundary.m"; "$WORK/boundary"
  build guard "$TESTDIR/native_guard.m"
  "$WORK/guard" fresh; "$WORK/guard" saved; "$WORK/guard" blocked; "$WORK/guard" late
  xcrun --sdk macosx clang -fobjc-arc -fobjc-arc-exceptions -fblocks -Wall -Wextra -Werror -Wno-unused-parameter \
    -I "$TESTDIR/stubs" -I "$MAIN/Sources" -I "$ROOT/Sources" \
    "$TESTDIR/native_games.m" "$ROOT/Sources/WUNativeGameLogic.m" -framework Foundation -framework CoreGraphics -o "$WORK/games"
  "$WORK/games"
else
  echo 'SKIP full Objective-C production UI/hooks/guard tests: no xcrun/macOS SDK. Unified Apple CI required; no device or account test performed.'
  if [ "${WU_REQUIRE_APPLE_TESTS:-0}" = 1 ]; then exit 77; fi
fi
