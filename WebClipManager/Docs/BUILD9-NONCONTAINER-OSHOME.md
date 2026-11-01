# Build9: explicit noncontainer, OS HOME unchanged

Status: a single device-unverified candidate, not a demonstrated sandbox fix.

## Evidence and competing hypotheses

1. Explicit container identity may affect the launch access outcome. Test the coherent noncontainer pair only: container-required=false plus no-container=true; all six other build8 entitlements stay unchanged. Prediction: installed runtime values match and fixed-path open/read-data denial disappears, while UIKit and main UI remain usable.
2. The prior sandbox_check no-report bit might be an instrumentation assumption. The PATH enum is 1 and the variadic C signature is correct, but NO_REPORT is an exported enum object. Resolve it with dlsym, dereference once, or use plain PATH when absent. Record filterType and symbol availability. Actual open/EPERM is independent evidence and is not invalidated by this probe refinement.
3. Other effective sandbox/launch rules may remain after the pair changes. Prediction: runtime matches yet actual open and read-data remain denied. Stop after this candidate rather than add unrelated storage/root capabilities.

Build7 mixed noncontainer mode with HOME rebinding; it cannot isolate either as the crash cause. Build9 keeps the OS environment unchanged, with build8 UIKit startup and in-memory logs. UIKit registration is not proof of the kernel profile's root cause.

## Primary sources reviewed

- TrollStore 2.1 RootHelper/main.m, lines 609–704: https://github.com/opa334/TrollStore/blob/2.1/RootHelper/main.m#L609-L704 . Explicit false survives container entitlement insertion.
- TrollStore 2.1 RootHelper/uicache.m, lines 45–81: https://github.com/opa334/TrollStore/blob/2.1/RootHelper/uicache.m#L45-L81 . false/no-container determines noncontainer registration; OS launch HOME=/var/mobile, TMPDIR=/var/tmp. This is installation behavior, not a demonstrated sandbox profile explanation.
- https://github.com/NSAntoine/Santander/blob/main/entitlements-TS.plist and https://github.com/NSAntoine/Santander/blob/main/Makefile : main/helper use the explicit pair. Other broad rights and setuid helper are deliberately NOT copied.
- https://github.com/dompling/TrollScript-Release/releases/tag/latest : reviewed 3.0.5 release executable has this pair, platform/no-sandbox, plus many other rights. Its main implementation is private; this is a signed-binary precedent, not open-source proof of its file-read mechanism. Do not infer its helper execution path.
- https://github.com/theos/headers/blob/master/sandbox.h : enum PATH=1; sandbox_check(pid_t,const char*,enum,...); NO_REPORT declared extern const enum. No private header/source copied into the application.

Sources fetched with verified TLS for this review. No user diagnostic file or its contents are part of this document/repository upload.

## Write boundary and UI

No setenv/unsetenv, root/persona helper, preference swizzling, mkdir/chmod, generic Documents access, new storage entitlements, or delete enablement. App state and logs remain in memory. App code uses no UserDefaults/AppStorage/SceneStorage. UIKit/SwiftUI can internally use system-managed preferences for this bundle identity; this candidate does NOT claim to redirect all framework preferences to a dedicated directory, or prove their noncontainer device behavior. It intentionally avoids inventing a global defaults/HOME rebind as a second experimental factor. No app-owned preference persistence is introduced.

AppPaths remains validation-only. Noncontainer HOME fails the existing app-container check, so file import/export presentation bindings stay false; there is no fallback to /var/mobile/Documents or /var/tmp. No directories are created or altered. Fixed-path diagnostics are explicit button actions, metadata/open only. Main UI is available regardless of AppPaths.ready and does not auto-scan. Notes read/parse logic and read-only SQLite strategy are unchanged.

## Regression/acceptance

- New policy test first failed against build8; after change checks exactly eight reviewed entitlements, no environment mutation/helper/persistent preferences, independent UIKit diagnostics, gated file panels, and runtime-resolved sandbox flag.
- XCTest adds noncontainer path rejection and environment preservation, checks eight runtime values and PATH bit; retains existing startup/no-auto-scan, Notes and read-only tests.
- Local captured device read-data acceptance is red; no simulator/static test can turn that real-device signal green.
- Device action: collect/copy homepage diagnostics, then open main interface. Accept only if eight entitlements match, all three fixed-path read-data results are zero, corresponding actual directory opens succeed, and main UI appears without scan. A later explicit Notes/WebClip read is needed to prove full data use; directory acceptance alone does not prove it.
- If denial persists or startup regresses, this candidate is not a completed repair. No entitlement expansion or further candidate is implied.
