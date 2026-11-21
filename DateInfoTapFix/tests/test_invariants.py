#!/usr/bin/env python3
"""Static invariants for the DateInfoTapFix companion tweak.

These run in CI before the Theos build so a safety regression fails the run
instead of reaching a device. They only read source text; nothing is executed
on a phone and no simulator is involved.
"""

import plistlib
import re
import sys
from pathlib import Path

p = Path(__file__).resolve().parents[1]
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


source = (p / "DateInfoTapFix.x").read_text(encoding="utf-8")
makefile = (p / "Makefile").read_text(encoding="utf-8")
control = (p / "control").read_text(encoding="utf-8")
plist = plistlib.loads((p / "DateInfoTapFix.plist").read_bytes())

# Packaging shape: SpringBoard only, RootHide scheme, both slices.
check(plist == {"Filter": {"Bundles": ["com.apple.springboard"]}},
      "plist must inject into com.apple.springboard only")
check("Package: local.dateinfo.tapfix\n" in control, "control package id")
check("Version: 1.0.0\n" in control, "control version")
check("Architecture: iphoneos-arm64e\n" in control, "control architecture")
check("ARCHS = arm64 arm64e" in makefile, "both architectures")
check("THEOS_PACKAGE_SCHEME = roothide" in makefile, "RootHide scheme")
check("DateInfoTapFix_FILES = DateInfoTapFix.x" in makefile, "source list")
check("-fobjc-arc" in makefile, "ARC enabled")

# Only the status bar foreground view is hooked, and only layoutSubviews.
hooks = re.findall(r"%hook\s+(\S+)", source)
check(hooks == ["_UIStatusBarForegroundView"], "exactly one hook target: %r" % (hooks,))
check(source.count("%orig") == 1, "one %orig call")

# The fix must never patch the tweak or intercept touches itself.
for forbidden in ["MSHook", "method_exchangeImplementations", "class_replaceMethod",
                  "sendEvent:", "UIWindow setHidden:", "NSURLSession", "CFPreferencesSet",
                  "openURL", "UITouch", "addSubview:self.view.window"]:
    check(forbidden not in source, "source must not contain %s" % forbidden)

# No disk writes and no network.
for forbidden in ["NSFileManager", "writeToFile", "NSUserDefaults", "NSString stringWithContentsOfFile"]:
    check(forbidden not in source, "no persistence: %s" % forbidden)

# The action is addressed by name and only after a respondsToSelector check.
check('kDIHotspotActionName = @"handleTap:"' in source, "action name")
check("respondsToSelector:action" in source, "guarded action call")
check("performSelector:action withObject:recognizer" in source, "action invocation")
check(source.index("respondsToSelector:action") < source.index("performSelector:action withObject:recognizer"),
      "responsiveness must be checked before the call")

# The recognizer state is restored after the call.
check('valueForKey:@"state"' in source, "state read through KVC")
check('setValue:@(kDIStateEnded) forKey:@"state"' in source, "state moved to ended")
check("setValue:savedState" in source, "state restored")

# Selector ivar read is guarded before use: inside the reader, the value is
# tested with sel_isMapped before it can leave the function.
reader_start = source.index("static SEL DIReadActionIvar")
reader_end = source.index("static BOOL DIFindTargetOnRecognizer")
reader_body = source[reader_start:reader_end]
check("sel_isMapped(stored)" in reader_body, "selector guarded by sel_isMapped")
check(reader_body.index("sel_isMapped(stored)") < reader_body.index("return stored;"),
      "the mapped check precedes the returned selector")
check("memcpy(&stored, slot, sizeof(stored))" in reader_body, "selector read from its slot")

# Hotspot geometry matches the tweak: 74 x 38 at two points down.
check("CGRectMake(centerX - 37.0, 2.0, 74.0, 38.0)" in source, "hotspot rectangle")
check("0.1633 : 0.107" in source, "center factor branch")
check("bounds.size.width < 200.0" in source, "narrow status bar guard")

# The forwarding recognizer must not swallow the tap.
check("cancelsTouchesInView = NO" in source, "does not cancel touches")

if failures:
    print("DateInfoTapFix invariants: FAIL")
    for failure in failures:
        print("  - " + failure)
    sys.exit(1)

print("DateInfoTapFix invariants: PASS")

