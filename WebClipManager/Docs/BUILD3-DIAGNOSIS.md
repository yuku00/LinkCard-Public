# Build 3: staged launch diagnosis, not a confirmed crash fix

No affected iOS 16.6 device or crash trace is available to CI. Therefore the actual immediate-exit regression cannot be reproduced unattended here. This build supplies a human-in-the-loop, three-stage experiment instead of claiming that simulator/static checks reproduce it.

## Read-only same-repository comparison

Inspected LinkCard-Public tree, workflows, source and Actions artifact 12622681290 (LinkCard 0.9.2 build 28). No other project was changed; no releases were created. No releases were returned by the releases API. LinkCard's checked-in workflow currently names build24, so the downloaded build28 IPA, not the workflow label, is the binary authority.

Both actual IPAs (LinkCard28 and WebClip2): minimum iOS16.0, Xcode16.4, iphoneos18.5 SDK, arm64 required; no embedded Frameworks; no UIApplicationSceneManifest. Both source entries use SwiftUI App/WindowGroup, Swift language mode5. LinkCard has LSRequiresIPhoneOS=true; WebClip2 omits it. This omission alone is not established as a launch failure. LinkCard has the NFC TAG entitlement; WebClip only has no-sandbox. These are different requirements, not evidence that NFC/platform/JIT entitlement should be copied. Of WebClip's strong _swift_* imports, only defaultActor_initialize/destroy/deallocate are absent from LinkCard; these are baseline actor runtime operations, not proven unavailable APIs. LinkCard itself is not independently verified as launchable on this particular device; the user reports other TrollStore apps launch, lowering the likelihood of a global registration failure.

## Symbol evidence beyond load commands

Parsed actual build2 LC_SYMTAB nlist_64, excluding STAB debug entries, retaining library ordinals and N_WEAK_REF: 680 undefined imports, 27 weak. Compared 241 SwiftUI imports and 20 concurrency imports with theos/sdks iPhoneOS16.5 SDK .tbd files. All concurrency imports and all strong SwiftUI imports have matching symbol strings. Only the weak WindowGroup.init(id:title:lazyContent:) import lacks a match. This is a secondary SDK-stub comparison, not the device's iOS16.6 dyld shared-cache export set and not a complete dyld binding proof. Weak absent symbols may still crash if invoked without proper fallback. No confirmed new strong SwiftUI/concurrency symbol was found. iOS16 already provides the concurrency runtime; an absent embedded libswift_Concurrency is not itself a defect. No speculative compatibility library, compiler switch or entitlement has been added.

## Experiment and predictions

1. Pre-main/registration/dyld/runtime-loading failure: no new S0_MAIN line, no UIKit page. SwiftUI and Swift libraries remain linked in the same executable, so deferring view construction does not isolate their pre-main binding. No log can prove which pre-main cause occurred; failed log creation is also possible.
2. SwiftUI App lifecycle, root construction or metadata failure: UIKit appears (S3), then pressing open fails between S4 and S6/S7. The original App lifecycle is replaced, but original RootView, models and views are retained. S6 callbacks and S7 completion may occur in either order.
3. Concurrency task/actor or filesystem stage: SwiftUI appears without data; manual refresh writes S8 before Task, S9 on async refresh entry, S10 upon Repository actor entry, S11 when scan returns/throws. A failure after return may instead be rendering/memory pressure. Ordinary read errors are caught and are not process-crash proof.

Log is Documents/startup-build3.log, synchronously flushed, bounded approximately64KiB. It contains epoch time, build number, OS version/build and fixed stages only, no URL, title, note content, identifiers, counts or raw error descriptions. File sharing and open-in-place are enabled. Relaunch preserves earlier markers; a new S0 separates attempts. Export from the UIKit page or retrieve via Files/Finder app Documents. No signal handler attempts unsafe I/O at crash time.

## Minimal device test

Install build3 with TrollStore. Open it: report whether 'UIKit 启动成功 · build3' appears. If yes press '打开 SwiftUI（不读取）'; if it appears press refresh once. Stop at first failure. Relaunch and export startup-build3.log, or retrieve via file sharing if UI cannot open. Do not test Notes, backup or deletion for this experiment. Provide iPhone model, exact iOS16.6 build (stable/beta), and TrollStore version if no stage log is available.

## Registration reference

Official https://github.com/opa334/TrollStore/blob/main/README.md says CoreTrust installs launchable System registrations; User registrations can fail FrontBoard/libmis launch validation. This is a per-app installation-state possibility, not a reason to ask this user to refresh all working apps. System registration does not mean adding platform-application entitlement. Entitlements remain unchanged.

## Validation boundaries

Added simulator tests for plain UIKit controller and original ManagerView mounting without automatic scanning. Existing synthetic tests remain. They cannot establish iOS16.6 device launch compatibility. CI retains nm -m -u output, Swift compiler version and Swift-related build settings with toolchain.txt. Build3 is diagnostic and needs the staged device result before any claim of root cause or fix.
