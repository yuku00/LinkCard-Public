# Build8 — restore container startup; collect evidence before SwiftUI

Target: iPhone14 / iOS16.6 / TrollStore2.1. Build6's main UI was device-confirmed usable; WebClips/Notes reads returned EPERM. Build7 changed both signing/container mode and HOME initialization. This revision restores both together; it does not claim device access or crash resolution.

## Changes and boundaries

- Restore exactly build6's seven entitlements: platform-application, own application-identifier, own string container-required, no-sandbox, AppDataContainers/Notes/Safari storage. Remove no-container and app-sandbox=false. These are requested entitlements, not proof of runtime authorization.
- Remove pre-main AppPaths.prepare and all HOME/CFFIXED_USER_HOME/TMPDIR mutation. Use OS-supplied container paths; validate only on explicit main-interface entry. No mkdir/chmod of shared paths. Validation failure is shown as a status and disables file import/export, not memory diagnostics.
- UIKit homepage shows selectable, scrollable memory logs with an always-enabled Copy button. No log file, fileExporter or SwiftUI required. Logs are only this process; reopening cannot recover an earlier crash.
- Homepage manual diagnostics resolves SecTask APIs and sandbox_check only after tapping. It captures typed/redacted values for the seven keys, operation-specific sandbox checks, existing fixed-directory open/lstat/realpath/fstat results and numeric errno. No readdir, Notes discovery, database open, contents or arbitrary user paths. AppGroup-root access does not prove access to the Notes child/database. Unknown API results are not interpreted as permission success.
- Notes parsing, confirmed read/export flow and disabled deletion remain unchanged. No root helper, blanket path exception, or broad entitlement bundle.

## Absolute-path read-only exception assessment

Primary source checked: Apple, App Sandbox Temporary Exception Entitlements:
https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html

Its opening note explicitly says these keys describe macOS App Sandbox and are **not available in iOS**. It documents `com.apple.security.temporary-exception.files.absolute-path.read-only`, but this is not evidence that it changes the iOS16.6 profile. No verified iOS16.6 policy/source demonstrating a bounded WebClips/Notes exception is available in this investigation. Therefore no speculative exception is added. A broad AppGroup parent exception would not be a narrow Notes-only grant. This round restores the UI configuration and gathers runtime evidence rather than promising EPERM resolution.

## Regression loop

Before patch: `python3 Tools/test_build8_policy.py` failed on container-required type/value. After patch this contract checks container signing, absence of environment mutation/pre-main prepare, and independent selectable/copyable diagnostics. This is a static regression, not a reproduction of the physical-device crash.

XCTest now drives StartupViewController.openButton -> UIHostingController<RootView> -> root/manager appearance and presentation completion, asserting no scan starts. It separately verifies diagnostics and copy while AppPaths.ready=false and asserts HOME/CFFIXED_USER_HOME/TMPDIR plus Foundation paths stay unchanged. Other Notes/SQLite/WAL/protobuf/repository tests continue using synthetic fixtures. CI also builds an arm64 iOS16-minimum device app and checks actual Mach-O XML/DER entitlements, version and CodeDirectory hashes.

## Minimal physical-device check

1. Install the separate build8 IPA yourself. On the UIKit homepage tap “采集运行权限与固定路径诊断”, then “复制当前日志与诊断”; save/send that text before opening SwiftUI.
2. Tap “打开主界面” once. Report whether it appears or exits. Do not initially refresh, read Notes or test deletion. If it appears, dismiss to the homepage and copy the current-process stages if useful.
3. If it exits, the previously copied report remains your evidence; this app does not claim to retain the crash log across restart. A system crash report is separate.

Simulator success, static signatures and compilation do not establish TrollStore/iOS16.6 runtime success.
