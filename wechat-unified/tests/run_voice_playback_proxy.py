#!/usr/bin/env python3
"""Run the production playback signature helper against Apple Foundation mocks."""
from pathlib import Path
import os, shutil, subprocess, sys
root=Path(__file__).resolve().parents[1]
if not shutil.which('xcrun'):
    print('SKIP: Apple SDK/xcrun unavailable; playback ObjC mocks not run')
    sys.exit(1 if os.environ.get('WU_REQUIRE_APPLE_TESTS')=='1' else 77)
build=root/'build/voice-proxy'; build.mkdir(parents=True,exist_ok=True)
source=(root/'Sources/Voice.m').read_text()
start=source.index('static BOOL Signature('); end=source.index('static id CallObject(',start)
(build/'voice_signature.inc').write_text(source[start:end])
subprocess.run(['xcrun','--sdk','macosx','clang','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror',
                '-I',str(build),str(root/'tests/voice_playback_proxy.m'),'-framework','Foundation',
                '-o',str(build/'test')],check=True)
subprocess.run([str(build/'test')],check=True)
