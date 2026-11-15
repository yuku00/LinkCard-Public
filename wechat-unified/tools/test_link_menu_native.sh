#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if ! command -v xcrun >/dev/null 2>&1; then echo 'SKIP link menu production mock: requires macOS Foundation runtime and Xcode'; exit 0; fi
WORK=$(mktemp -d /tmp/wu-link-menu.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
python3 - "$ROOT" "$WORK" <<'PY'
import pathlib,sys
src=(pathlib.Path(sys.argv[1])/'Sources/Core.m').read_text()
(pathlib.Path(sys.argv[2])/'menu_matches.inc').write_text(src[src.index('static const char *Unqualified('):src.index('BOOL WUHook(',src.index('static const char *Unqualified('))])
PY
for bad in 0 1; do
  xcrun --sdk macosx clang -fobjc-arc -fblocks -DWU_TEST_BAD_MENU_ABI=$bad -Wno-unused-parameter \
    -I "$ROOT/tests/native/stubs" -I "$ROOT/Sources" -I "$WORK" \
    "$ROOT/tests/link_menu_native.m" "$ROOT/tests/native/UIKitMock.m" \
    -framework Foundation -framework CoreGraphics -o "$WORK/menu-$bad"
  "$WORK/menu-$bad"
done
