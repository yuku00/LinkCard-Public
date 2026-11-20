#!/usr/bin/env python3
"""Static integration checks; not a substitute for an on-device test."""
from pathlib import Path
import plistlib
p = Path(__file__).resolve().parents[1]
s = (p / 'DateInfoProbe.m').read_text()
t = (p / 'DITapProbe.inc').read_text()
c = (p / 'control').read_text()
m = (p / 'Makefile').read_text()
assert plistlib.loads((p / 'DateInfoProbe.plist').read_bytes()) == {'Filter': {'Bundles': ['com.apple.springboard']}}
assert 'Package: local.dateinfo.probe\n' in c and 'Version: 0.2.0\n' in c
assert 'ARCHS = arm64 arm64e' in m and 'THEOS_PACKAGE_SCHEME = roothide' in m
assert '#include "DITapProbe.inc"' in s
for x in ('loadDocument(); DITapProbeBegin();', 'scanTapBindings();', 'DITapProbeEnd(); tapReport = DITapProbeReport(); flushDocument();', 'seconds = 15; seconds <= 95; seconds += 5', '105*NSEC_PER_SEC', '35*NSEC_PER_SEC', 'old[@"samples"] mutableCopy', 'NSDataWritingAtomic'):
    assert x in s, x
for x in ('strrchr(path, \'/\')', 'strcmp(base ? base + 1 : path, "DateInfo.dylib")', 'class_getImageName(cls)', 'dladdr(imp, &info)', 'diCandidates >= 4096', 'diRegistrations >= 128', '[diBindings objectForKey:g]', 'addTarget:diCounter', 'removeTarget:diCounter', '@"unknown"', '@"private_target_layout_unreadable_count"'):
    assert x in t, x
for x in ('MSHook', 'method_exchangeImplementations', 'NSURLSession', 'CFPreferencesSet', 'openURL', 'sendEvent:', 'UITouch'):
    assert x not in s + t, x
print('static integration checks: PASS (no simulator or XCTest)')
