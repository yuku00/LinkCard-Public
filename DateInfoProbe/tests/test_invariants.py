#!/usr/bin/env python3
"""Static checks plus a native C mock of the actual trigger predicate; no simulator."""
from pathlib import Path
import plistlib, subprocess, tempfile
p = Path(__file__).resolve().parents[1]
s = (p / 'DateInfoProbe.m').read_text()
t = (p / 'DITapProbe.inc').read_text()
c = (p / 'control').read_text()
m = (p / 'Makefile').read_text()
assert plistlib.loads((p / 'DateInfoProbe.plist').read_bytes()) == {'Filter': {'Bundles': ['com.apple.springboard']}}
assert 'Version: 0.4.0\n' in c
assert 'ARCHS = arm64 arm64e' in m and 'THEOS_PACKAGE_SCHEME = roothide' in m
for x in ('#include "DITapProbe.inc"', 'O_CREAT | O_EXCL | O_NOFOLLOW', '20*NSEC_PER_SEC', '2*NSEC_PER_SEC', 'monotonic()+600', '>= 90', 'queueIndex + 100', 'queue.count >= 10000', 'records.count < 20', 'diClassAvailableScans++', 'diClassMissingScans++', 'DITapProbeEnd()', '@"stage_observations":delta', 'diWindowInventory()'):
    assert x in s, x
for x in ('class_getImageName(cls)', 'dladdr(imp, &info)', 'diCandidates >= 4096', 'diRegistrations >= 128', 'addTarget:diCounter', 'removeTarget:diCounter'):
    assert x in t, x
# v0.4: the stored selector is named, but only after sel_isMapped proves it is
# dereferenceable, and binding no longer depends on the selector comparison.
for x in ('sel_isMapped((SEL)raw)', 'sel_getName(named)', 'ptrauth_blend_discriminator', 'hitTest:centre withEvent:nil', 'bindings_by_target_class_only', 'selector_match_by_name'):
    assert x in t, x
assert t.index('sel_isMapped((SEL)raw)') < t.index('sel_getName(named)')
assert t.index('SEL named =') < t.index('sel_getName(named)')
for x in ('MSHook', 'method_exchangeImplementations', 'NSURLSession', 'CFPreferencesSet', 'openURL', 'sendEvent:', 'UITouch'):
    assert x not in s + t, x
# Compile the real predicate with mocked syscalls to exercise acceptance and failure paths.
predicate = s[s.index('static BOOL validTrigger(void) {'):s.index('static void finish(void) {')]
harness = r'''
#include <stdio.h>
#include <assert.h>
#include <time.h>
#include <sys/stat.h>
#include <fcntl.h>
typedef int BOOL;
#define YES 1
#define NO 0
static const char *triggerPath = "/mock";
static time_t injectionSecond = 100;
static struct stat fake;
static int openFail, statFail, closeCount, flagsSeen;
static int myopen(const char *p, int flags) { (void)p; flagsSeen=flags; return openFail ? -1 : 7; }
static int myfstat(int fd, struct stat *s) { assert(fd==7); *s=fake; return statFail ? -1 : 0; }
static int myclose(int fd) { assert(fd==7); closeCount++; return 0; }
static time_t mytime(time_t *p) { (void)p; return 200; }
#define open myopen
#define fstat myfstat
#define close myclose
#define time mytime
''' + predicate + r'''
int main(void) {
 fake.st_mode=S_IFREG; fake.st_size=0; fake.st_uid=501; fake.st_mtime=101;
 assert(validTrigger()); assert((flagsSeen & O_NOFOLLOW) != 0); assert(closeCount==1);
 fake.st_uid=0; assert(!validTrigger()); fake.st_uid=501;
 fake.st_size=1; assert(!validTrigger()); fake.st_size=0;
 fake.st_mode=S_IFDIR; assert(!validTrigger()); fake.st_mode=S_IFREG;
 fake.st_mtime=100; assert(!validTrigger()); fake.st_mtime=201; assert(!validTrigger()); fake.st_mtime=101;
 statFail=1; assert(!validTrigger()); statFail=0; openFail=1; assert(!validTrigger());
 puts("trigger predicate mock: PASS"); return 0;
}
'''
with tempfile.TemporaryDirectory() as d:
    src = Path(d)/'mock.c'; src.write_text(harness)
    subprocess.run(['clang', '-std=gnu11', '-Wall', '-Wextra', '-Werror', str(src), '-o', str(Path(d)/'mock')], check=True)
    subprocess.run([str(Path(d)/'mock')], check=True)
print('static integration checks: PASS (no simulator or XCTest)')
