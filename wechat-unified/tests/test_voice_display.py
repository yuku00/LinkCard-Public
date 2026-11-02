"""Run actual portable policy + Apple production getter/binding mocks.
A missing SDK is an explicit NOT RUN, never a claimed Objective-C pass.
"""
from pathlib import Path
import os, shutil, subprocess
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
def main():
    BUILD.mkdir(exist_ok=True)
    cc=os.environ.get('CC') or shutil.which('cc') or shutil.which('gcc')
    if not cc:
        raise SystemExit('C compiler required')
    exe=BUILD/'voice-display-policy-tests'
    subprocess.run([cc,'-std=c11','-Wall','-Wextra','-Werror','-I','Sources',
                    'tests/voice_display_policy.c','-lm','-o',str(exe)],cwd=ROOT,check=True)
    loader=Path('/lib/ld-musl-aarch64.so.1')
    command=[str(loader),str(exe)] if loader.is_file() else [str(exe)]
    subprocess.run(command,cwd=ROOT,check=True)
    exe.unlink()
    if not shutil.which('xcrun'):
        print('NOT RUN: Apple SDK/Foundation hostmock and iOS UIKit syntax checks')
        if os.environ.get('WU_REQUIRE_APPLE_TESTS')=='1': raise SystemExit(2)
        return
    core=(ROOT/'Sources/Core.m').read_text()
    voice=(ROOT/'Sources/Voice.m').read_text()
    helpers=[BUILD/'voice_display_matches.inc',BUILD/'voice_display_binding.inc',BUILD/'voice_display_layout.inc']
    helpers[0].write_text(core[core.index('static const char *Unqualified'):core.index('BOOL WUHook(')])
    start=voice.index('- (void)clearDisplay {')
    helpers[1].write_text(voice[start:voice.index('- (void)clear {',start)])
    helpers[2].write_text(voice[voice.index('static void Layout('):voice.index('static void Window(')])
    exe=BUILD/'voice-display-native-tests'
    try:
        subprocess.run(['xcrun','--sdk','macosx','clang','-fobjc-arc','-fobjc-arc-exceptions',
            '-fblocks','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-I','Sources','-I','build',
            'tests/voice_display_native.m','Sources/VoiceDisplay.m','Sources/VoiceLogic.m',
            '-framework','Foundation','-o',str(exe)],cwd=ROOT,check=True)
        for mode in ('normal','missing','bad-type'):
            subprocess.run([str(exe),mode],cwd=ROOT,check=True)
    finally:
        for p in [exe,*helpers]: p.unlink(missing_ok=True)
if __name__=='__main__': main()
