#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if ! command -v xcrun >/dev/null 2>&1; then
  echo 'SKIP (77): Apple SDK/runtime unavailable; native mock NOT RUN'
  exit 77
fi
WORK=$(mktemp -d /tmp/wu-host-service.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
python3 - "$ROOT" "$WORK" <<'PY'
import pathlib,sys
root,work=map(pathlib.Path,sys.argv[1:])
core=(root/'Sources/Core.m').read_text()
(work/'core_match.inc').write_text(core[core.index('static const char *Unqualified'):core.index('BOOL WUHook(')])
s=(root/'Sources/Messages.m').read_text()
helpers=s[s.index('static BOOL Has('):s.index('static uint64_t Num(')]
account=s[s.index('static id Service('):s.index('NSString *WUCurrentAccount(')]
account=account.replace('static id Service(NSString *name) { return WUHostService(name); }\n', '')
(work/'account.inc').write_text(helpers+account)
PY
for bad in 0 1; do
  xcrun --sdk macosx clang -fobjc-arc -fobjc-arc-exceptions -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -DBAD_CONTEXT=$bad -I "$ROOT/Sources" -I "$WORK" "$ROOT/tests/host_service_native.m" "$ROOT/Sources/WUHostService.m" -framework Foundation -o "$WORK/test"
  "$WORK/test"
  "$WORK/test" subclass
  "$WORK/test" missing
done
