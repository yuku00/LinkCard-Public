#!/bin/sh
set -eu
TESTDIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GAP=${WU_GAP_SOURCE:-$(CDPATH= cd -- "$TESTDIR/../.." && pwd)}
MAIN=${WU_MAIN_SOURCE:?set WU_MAIN_SOURCE to the read-only baseline or the merged project}
WORK=$(mktemp -d /tmp/wu-native-gaps.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
python3 "$MAIN/tests/native/extract_core.py" "$MAIN/Sources/Core.m" "$WORK/core_hooks.inc"
if ! command -v xcrun >/dev/null 2>&1; then
    echo 'SKIP (77): no Apple SDK/runtime; production Objective-C tests NOT RUN. Run in unified Apple CI.'
    exit 77
fi
source_file() {
    if [ -f "$GAP/Sources/$1" ]; then echo "$GAP/Sources/$1"; else echo "$MAIN/Sources/$1"; fi
}
xcrun --sdk macosx clang -std=c11 -Wall -Wextra -Werror -I "$MAIN/Sources" -c "$MAIN/Sources/WUNativeBoot.c" -o "$WORK/boot.o"
build() {
    name=$1; shift
    xcrun --sdk macosx clang -fobjc-arc -fobjc-arc-exceptions -fblocks -Wall -Wextra -Werror -Wno-unused-parameter \
        -I "$MAIN/tests/native/stubs" -I "$GAP/Sources" -I "$MAIN/Sources" -I "$MAIN/tests/native" -I "$WORK" \
        -include "$MAIN/tests/native/clock.h" "$@" "$MAIN/tests/native/UIKitMock.m" "$MAIN/tests/native/TestHost.m" \
        "$(source_file WUNative.m)" "$(source_file WUNativeEntries.m)" "$(source_file WUNativeSettings.m)" \
        "$MAIN/Sources/WUNativeAction.m" "$MAIN/Sources/WUNativeRecovery.m" "$MAIN/Sources/WUNativeInteractions.m" \
        "$MAIN/Sources/WUNativeGames.m" "$MAIN/Sources/WUNativeGameLogic.m" "$MAIN/Sources/MessageConstruction.m" "$WORK/boot.o" \
        -framework Foundation -framework CoreGraphics -o "$WORK/$name"
}
build entries "$TESTDIR/native_entries.m"; "$WORK/entries"
build entries_bad -DWU_TEST_ENTRY_BAD_ABI=1 "$TESTDIR/native_entries.m"; "$WORK/entries_bad"
build boundary -DWU_NATIVE_BOUNDARY_TEST=1 "$TESTDIR/native_boundary.m"; "$WORK/boundary"
# The default production build MUST still reject enabling unknown real host loaders.
build fail_closed "$MAIN/tests/native/native_hooks.m"; "$WORK/fail_closed"
