#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d /tmp/wu-emoticon-tests.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
cc -std=c11 -Wall -Wextra -Werror -I "$ROOT/Sources" "$ROOT/tests/emoticon_library_atomic.c" -o "$WORK/atomic"
"$WORK/atomic"
python3 "$ROOT/tests/test_emoticon_library_contract.py"
if ! command -v xcrun >/dev/null 2>&1; then
  echo 'SKIP (77): no Apple SDK; real Foundation/ImageIO store + hostmock submission + UIKit syntax tests NOT RUN.'
  exit 77
fi
python3 - "$ROOT" "$WORK" <<'PY'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:])
core=(root/'Sources/Core.m').read_text()
(work/'emoticon_matches.inc').write_text(core[core.index('static const char *Unqualified'):core.index('BOOL WUHook(')])
PY
for mode in normal bad; do
  if [ "$mode" = bad ]; then set -- -DWU_EMOTICON_BAD_FACTORY=1; else set --; fi
  xcrun --sdk macosx clang "$@" -fobjc-arc -fobjc-arc-exceptions -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -I "$ROOT/Sources" -I "$WORK" \
    "$ROOT/tests/emoticon_library_native.m" "$ROOT/Sources/EmoticonLibraryLogic.m" "$ROOT/Sources/EmoticonSubmission.m" "$ROOT/Sources/EmoticonLogic.m" "$ROOT/Sources/MessageConstruction.m" "$ROOT/Sources/DraftMediaLogic.m" \
    -framework Foundation -framework CoreGraphics -framework ImageIO -lz -o "$WORK/native-$mode"
  "$WORK/native-$mode"
done
xcrun --sdk macosx clang -fobjc-arc -fobjc-arc-exceptions -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -I "$ROOT/Sources" "$ROOT/tests/group_logic.m" "$ROOT/Sources/GroupLogic.m" "$ROOT/Sources/HomeLogic.m" -framework Foundation -o "$WORK/groups"
"$WORK/groups"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=16.6 -fobjc-arc -fobjc-arc-exceptions -fblocks -fsyntax-only -Wall -Wextra -Werror -Wno-unused-parameter -Wno-nullability-completeness "$ROOT/Sources/EmoticonLibrary.m" "$ROOT/Sources/Messages.m" "$ROOT/Sources/Groups.m"
