#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
umask 077
cd "$(dirname "$0")"
OUT="$PWD/out"
mkdir -p "$OUT"
# This script accepts no input path/URL: only its own fixture.c is analyzed.
[ "$#" -eq 0 ] || { echo 'No arguments accepted'; exit 2; }
[ "$(uname -m)" = x86_64 ] || { echo 'Requires x86_64 runner'; exit 2; }
: "${RUNNER_TEMP:?GitHub temporary workspace required}"
if [ -n "${JAVA_HOME_25_X64:-}" ]; then
  export JAVA_HOME="$JAVA_HOME_25_X64"
  export PATH="$JAVA_HOME/bin:$PATH"
fi
python3 - <<'PY'
import subprocess,re,pathlib,shutil
for tool in ['java','javac','clang','curl','unzip','timeout']:
    if not shutil.which(tool): raise SystemExit('Missing preinstalled tool: '+tool)
for tool in ['java','javac']:
    r=subprocess.run([tool,'-version'],text=True,capture_output=True)
    text=r.stdout+r.stderr
    if r.returncode or not re.search(r'(?:version\s+"|javac\s+)25(?:[.\s"+-]|$)',text):
        raise SystemExit('Preinstalled JDK 25 required; no automatic installation')
    pathlib.Path('out/'+tool+'-version.txt').write_text(text)
free=shutil.disk_usage('.').free
if free < 5*1024**3: raise SystemExit('Need at least 5 GiB free temporary disk')
PY
TMP="$(mktemp -d "$RUNNER_TEMP/ghidra-smoke.XXXXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
URL='https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.2_build/ghidra_12.2_PUBLIC_20261016.zip'
SHA='2c2cd776db3c1f6a097ba418922378ac3649cadd5e844a6f5f088ae628a7be67'
curl -q --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
  --retry 2 --connect-timeout 30 --max-time 360 "$URL" -o "$TMP/ghidra.zip"
[ "$(stat -c '%s' "$TMP/ghidra.zip")" -eq 569712708 ]
printf '%s  %s\n' "$SHA" "$TMP/ghidra.zip" | sha256sum --check -
unzip -q "$TMP/ghidra.zip" -d "$TMP"
GHIDRA="$TMP/ghidra_12.2_PUBLIC"
[ -x "$GHIDRA/support/analyzeHeadless" ]
cp "$GHIDRA/Ghidra/application.properties" "$OUT/ghidra-application.properties"
clang --version > "$OUT/clang-version.txt"
# Native source contract checks are separate from decompiler correctness.
clang -std=c11 -Wall -Wextra -Werror -O1 -DWU_HOST_TEST fixture.c -o "$TMP/source-test"
"$TMP/source-test"
clang -target arm64-apple-macos11 -std=c11 -O1 -fno-stack-protector -c fixture.c -o "$OUT/fixture-arm64.o"
python3 - <<'PY'
import struct,pathlib
b=pathlib.Path('out/fixture-arm64.o').read_bytes()
magic,cpu,subtype,filetype=struct.unpack_from('<IIII',b)
assert magic==0xfeedfacf and cpu==0x0100000c and filetype==1, (magic,cpu,filetype)
pathlib.Path('out/input-format.txt').write_text('Synthetic ARM64 Mach-O MH_OBJECT; no original plugin input\n')
PY
mkdir -p "$TMP/projects"
export GHIDRA_HEADLESS_MAXMEM=4G
# No external Swift tool is necessary for this C-only synthetic fixture.
timeout --signal=TERM --kill-after=30 360 \
  "$GHIDRA/support/analyzeHeadless" "$TMP/projects" smoke \
  -import "$OUT/fixture-arm64.o" \
  -scriptPath "$PWD" \
  -postScript SmokeDecompile.java "$OUT" \
  -analysisTimeoutPerFile 180 -max-cpu 2 \
  -log "$OUT/synthetic-analysis.log" \
  -scriptlog "$OUT/synthetic-script.log" \
  > "$OUT/synthetic-console.log" 2>&1
python3 - <<'PY'
import pathlib,json,hashlib,os
p=pathlib.Path('out')
expected={'wu_clamp_score','wu_weighted_sum','wu_choose_mode'}
assert (p/'result.txt').read_text()=='PASS: 3/3 synthetic ARM64 Mach-O functions decompiled\n'
rows=[s.split('\t') for s in (p/'functions.tsv').read_text().splitlines()]
assert len(rows)==3 and {r[0] for r in rows}==expected and all(r[2]=='OK' for r in rows)
for n in expected: assert (p/(n+'.c.txt')).stat().st_size>80
manifest={'scope':'synthetic smoke ONLY; no user dylib or private analysis',
 'ghidra':'12.2','ghidra_zip_sha256':'2c2cd776db3c1f6a097ba418922378ac3649cadd5e844a6f5f088ae628a7be67',
 'commit':os.environ.get('GITHUB_SHA'),'run_id':os.environ.get('GITHUB_RUN_ID'),
 'functions':rows,'semantic_equivalence_proved':False,
 'files':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(p.iterdir()) if f.is_file()}}
(p/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('PASS: Ghidra native decompiler exported all three synthetic ARM64 Mach-O functions')
PY
