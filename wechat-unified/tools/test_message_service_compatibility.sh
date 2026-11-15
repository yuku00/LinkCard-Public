#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if ! command -v xcrun >/dev/null 2>&1; then
  echo 'SKIP (77): Apple SDK/runtime unavailable; service compatibility mock NOT RUN'
  exit 77
fi
WORK=$(mktemp -d /tmp/wu-message-service.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
python3 - "$ROOT" "$WORK" <<'PY'
import pathlib,sys
root,work=map(pathlib.Path,sys.argv[1:])
core=(root/'Sources/Core.m').read_text()
(work/'core_match.inc').write_text(core[core.index('static const char *Unqualified'):core.index('BOOL WUHook(')])
s=(root/'Sources/Messages.m').read_text()
(work/'request_revoke.inc').write_text(s[s.index('static NSString *RevokeSelector('):s.index('#import "ChatGrid.inc"')])
PY
xcrun --sdk macosx clang -fobjc-arc -fobjc-arc-exceptions -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -I "$ROOT/Sources" -I "$WORK" "$ROOT/tests/message_service_compatibility.m" -framework Foundation -o "$WORK/test"
"$WORK/test"
