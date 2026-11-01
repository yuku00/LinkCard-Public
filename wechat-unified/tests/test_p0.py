"""Compile exact production slices; only UIKit/host lookup is replaced, never the save or ABI gates."""
from pathlib import Path
import subprocess, sys
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'; BUILD.mkdir(exist_ok=True)

def between(text,start,end):
    return text[text.index(start):text.index(end)]

def compile_test(name, sources):
    subprocess.run(['xcrun','--sdk','macosx','clang','-fobjc-arc','-fobjc-arc-exceptions','-fblocks','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-I','Sources','-I','build',*sources,'-framework','Foundation','-o',str(BUILD/name)],cwd=ROOT,check=True)

def execute(name, args=()):
    p=subprocess.run([str(BUILD/name),*args],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    print(p.stdout,flush=True)
    (BUILD/(name+''.join(args)+'.txt')).write_text(p.stdout)
    return p

core=(ROOT/'Sources/Core.m').read_text()
groups=(ROOT/'Sources/Groups.m').read_text()
config=core[:core.index('static const char *Unqualified')].replace('#import "WU.h"','#import <Foundation/Foundation.h>')
config=config.replace('static NSMutableDictionary<NSString *, NSString *> *hooks;','')
config+='\nstatic NSString *currentAccount=@"A";\nNSString *WUCurrentAccount(void) { return currentAccount; }\n'
config+=between(groups,'NSDictionary *WUAccountOptions','static NSDictionary *EmojiState')
config+=(ROOT/'tests/p0_config.m').read_text()
(BUILD/'p0_config_generated.m').write_text(config)
compile_test('p0-config-tests',['build/p0_config_generated.m','Sources/GroupLogic.m','Sources/HomeLogic.m'])
config_result=execute('p0-config-tests')
messages=(ROOT/'Sources/Messages.m').read_text()
gate='#include <string.h>\n#include <stdlib.h>\n'
gate+=between(core,'static const char *Unqualified','BOOL WUHook(')
gate+=between(messages,'static BOOL Has(','static id Obj(')
gate+=between(messages,'static BOOL NumberSetter','static void SetNumber')
gate+=between(messages,'static BOOL RepeatReady','@interface WUCellActions')
(BUILD/'p0_repeat_gate.inc').write_text(gate)
if not (BUILD/'codec-macosx/libWUOffline.a').exists():
    subprocess.run([sys.executable,'tools/build_codecs.py','macosx'],cwd=ROOT,check=True)
sources=['tests/p0_message.m','Sources/VoiceSendLogic.m','Sources/VoicePackLogic.m','Sources/RepositoryLogic.m','Sources/DraftMediaLogic.m','build/codec-macosx/libWUOffline.a']
if (ROOT/'Sources/MessageConstruction.m').exists(): sources.append('Sources/MessageConstruction.m')
compile_test('p0-message-tests',sources)
results=[execute('p0-message-tests',[encoding]) for encoding in ('I','q','i','Q')]
if '--expect-red' in sys.argv:
    assert config_result.returncode==1 and 'FAIL configuration' in config_result.stdout, 'Configuration baseline did not fail its symptom'
    assert all(p.returncode==1 and 'FAIL shared constructor' in p.stdout for p in results), 'Conflicting ABI baseline did not fail its symptom'
    print('RED BASELINE PROVEN: production persistence fails; no single I/q/i/Q constructor enables repeat and voice/pack together.')
else:
    assert config_result.returncode==0 and all(p.returncode==0 for p in results), 'P0 production regression failed'
for name in ('p0-config-tests','p0-message-tests','p0_config_generated.m','p0_repeat_gate.inc'):
    (BUILD/name).unlink()
