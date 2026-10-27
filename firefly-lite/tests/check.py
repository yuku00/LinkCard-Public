#!/usr/bin/env python3
"""Host-only static, pure-C and simulated dpkg argument tests, never iOS tests."""
from pathlib import Path
import plistlib, subprocess, tempfile, os
root = Path(__file__).resolve().parents[1]
for path in root.rglob('*.plist'):
    plistlib.loads(path.read_bytes())
print('PASS: all property lists parse')
assert 'export THEOS_PACKAGE_SCHEME = roothide' in (root/'Makefile').read_text()
assert 'Package: dev.fireflylite.badgeglow\n' in (root/'control').read_text()
assert 'iphoneos-arm64e' in (root/'control').read_text()
assert plistlib.loads((root/'FireflyLite.plist').read_bytes())['Filter']['Bundles'] == ['com.apple.springboard']
source = '\n'.join(p.read_text() for p in root.rglob('*') if p.suffix in ('.m', '.mm', '.h'))
for forbidden in ('libCSColorPicker', 'NSURLSession', 'system(', 'popen(', 'posix_spawn(', 'killall', '/var/jb', 'xyz.cypwn', 'unlink('):
    assert forbidden not in source, forbidden
assert 'kCFPreferencesCurrentUser' in source and 'kCFPreferencesAnyHost' in source
assert 'CFNotificationCenterRemoveEveryObserver' in source
assert 'UIColorPickerViewController' in source
preferences = (root/'Shared/FLPreferences.m').read_text()
assert 'id allApps = FLGet(CFSTR("AllApps"));' in preferences
assert '[allApps isKindOfClass:NSNumber.class] && [allApps boolValue]' in preferences
assert '@"AllApps": @(!!c.allApps)' in preferences
assert 'CFPreferencesCopyKeyList(FL_DOMAIN' in preferences  # Clears the entire domain, including new keys.
assert 'CFPreferencesSetMultiple(NULL, keys, FL_DOMAIN' in preferences
assert 'config.enabled, config.allApps, badge, [view isFolderIcon]' in (root/'Tweak.mm').read_text()
assert 'Version: 0.1.1\n' in (root/'control').read_text()
print('PASS: AllApps read/default/write wiring, whole-domain cleanup and version checks')
print('PASS: package/domain/filter/dependency and prohibited API checks')
with tempfile.TemporaryDirectory(prefix='firefly-test-') as tmp:
    tmp = Path(tmp)
    binary = tmp/'logic'
    subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', str(root/'tests/logic.c'), '-lm', '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
    print('PASS: 25 native C boundary/visibility assertions (both modes, folders, master switch, zero intensity)')
    # Substitute only the helper location; preserve the actual maintainer logic.
    calls = tmp/'calls'
    helper = tmp/'helper'
    helper.write_text('#!/bin/sh\nprintf x >> "$FL_TEST_CALLS"\nexit "${FL_TEST_EXIT:-0}"\n')
    helper.chmod(0o755)
    script = tmp/'prerm'
    script.write_text((root/'layout/DEBIAN/prerm').read_text().replace('/usr/libexec/firefly-lite-cleanup', str(helper)))
    env = dict(os.environ, FL_TEST_CALLS=str(calls))
    cases = [( ['remove'], True ), (['upgrade', '0.2.0'], False),
             (['failed-upgrade', '0.2.0'], False),
             (['remove', 'in-favour', 'other', '1.0'], False),
             (['deconfigure', 'in-favour', 'other', '1.0'], False),
             ([], False)]
    for args, expect in cases:
        calls.unlink(missing_ok=True)
        subprocess.run(['sh', str(script), *args], check=True, env=env)
        assert calls.exists() == expect, args
    subprocess.run(['sh', str(script), 'remove'], check=True, env=dict(env, FL_TEST_EXIT='1'))
    print('PASS: 6 dpkg lifecycle argument cases; cleanup failure does not block removal')
print('NOT RUN: Objective-C/Apple SDK compilation, CFPreferences, UIKit, SpringBoard, install/remove on device')
