# C container permission probe — build4

## Evidence and scope

Device feedback: iPhone 14, iOS 16.6, TrollStore 2.1. Pure Objective-C A (empty entitlements) stays open; B (`com.apple.private.security.no-sandbox=true`) exits immediately. This narrows the problem to entitlement/install processing, but does NOT establish that no-sandbox is invalid. No automated device reproduction is available in this environment; successful compilation is not a startup regression pass.

Direct parsing of LC_CODE_SIGNATURE / XML entitlement slots in the downloaded original and build3 manager IPAs confirms their only entitlement is `com.apple.private.security.no-sandbox` boolean true. A has an empty dictionary; B has that same single true entitlement. These are pre-install signatures, NOT signatures after TrollStore re-signing.

## Primary sources, pinned

TrollStore 2.1 commit `d11c04666a77435d1ac142af1b0b749214d60a9a`:
- https://github.com/opa334/TrollStore/blob/d11c04666a77435d1ac142af1b0b749214d60a9a/README.md#unsandboxing explicitly lists three alternatives: `container-required=false`, `no-container=true`, `no-sandbox=true`. It recommends the last when a data container is desired. No evidence that no-sandbox is misspelled or categorically unsupported on iOS 16.6.
- https://github.com/opa334/TrollStore/blob/d11c04666a77435d1ac142af1b0b749214d60a9a/RootHelper/main.m#L608-L696 : normally injects `container-required=<bundleID>` for the new CoreTrust bypass, but skips insertion for no-sandbox/no-container true, explicit container-required false, or an existing string. Thus A and B may differ in installed container-required entitlement too.
- https://github.com/opa334/TrollStore/blob/d11c04666a77435d1ac142af1b0b749214d60a9a/RootHelper/uicache.m#L45-L82 : `no-container=true` or boolean `container-required=false` disables containerized registration. A STRING means a custom container identifier, NOT false. Home/tmp become `/var/mobile` and `/var/tmp` for uncontainerized apps. `no-sandbox` alone does not disable container registration here.
- README banned list on A12+ / iOS 15+: `com.apple.private.cs.debugger`, `dynamic-codesigning`, `com.apple.private.skip-library-validation`. None is present in the original signatures or C. iOS 16.6 is in the supported OS range; support does not guarantee every private entitlement works.
- main.m lines 650-668 separately marks true get-task-allow, task_for_pid-allow, com.apple.system-task-ports, com.apple.system-task-ports.control, com.apple.system-task-ports.token.control, com.apple.private.cs.debugger as requiring developer mode on iOS 16+. This list is not equivalent to the banned list. C has none.
- README and Shared/TSUtil.m lines 110-118: `persona-mgmt=true` enables root child spawning when combined with explicit persona/uid/gid spawn attributes. It does not automatically make a UIApplication root. Removing the sandbox does not bypass Unix DAC or Data Protection. C adds no persona permission and displays actual uid/euid.
- TrollStore/entitlements.plist uses `com.apple.security.exception.files.absolute-path.read-write` with an ARRAY of paths, together with platform/no-sandbox and additional privileges. A bare `com.apple.security.exception.files.absolute-path` key is not used there. This is a path-specific exception, not proof that it is a drop-in unsandboxing key. The README warns platform-application has sandbox side effects; proper CS_PLATFORMIZED/TF_PLATFORM is not supplied by TrollStore. Do not copy a broad entitlement list blindly.

Cross-check: public file manager Santander, commit `8ea2bec1a54b94517c65e3f44f70627481922813`:
- https://github.com/SerenaKit/Santander/blob/8ea2bec1a54b94517c65e3f44f70627481922813/entitlements-TS.plist uses container-required=false, no-container=true, absolute-path.read-write array, persona and many other permissions. Makefile and .github/workflows/build.yml explicitly select this TS plist. It supports the alternative's provenance, NOT a claim that C's minimal set has been tested on this device.
- Its ordinary entitlements.plist contains skip-library-validation, on TS's banned list. Do not copy the ordinary (non-TS) plist.
- No verified public iOS Filza/AppsManager source entitlement manifest was obtained. The similarly named jingyinglee/AppsManager is an Android project and was rejected as evidence.
- https://github.com/Bascter-Main/NotesExporter/blob/2c539be3f2b725d4038a8a74460848e214b558ac/NotesExporterTrollFools/Makefile builds a TWEAK/dylib injected into Notes, not a standalone app. Its process access cannot validate standalone app entitlements. No source from these external apps was copied.

## Hypotheses and experiment

Ranked before C: (1) install-time signature/container mismatch, (2) device-specific no-sandbox path behavior, (3) other signing restriction. We cannot distinguish (1) from (2) with the existing IPA files alone. No known-invalid entitlement was found, so changing the production app and calling it fixed is not justified.

Only C is built. Entitlements contain exactly ONE key:

    com.apple.private.security.container-required = false (boolean)

This tests the documented explicitly uncontainerized route instead of B's no-sandbox-with-container route. This is a hypothesis test, not a proven fix, and does not hold containerization constant. No platform, JIT, debugger, storage exemptions or root/persona rights are added. A/B source and main application stay unchanged. C has a separate bundle ID, `io.github.yuku00.webclip.startupprobe.c`, build number 4.

The launch path does no target-directory I/O. After a manual tap C uses open(O_RDONLY|O_DIRECTORY|O_CLOEXEC) and close on three fixed paths: WebClips, AppGroup root, legacy Notes. No readdir, directory-name enumeration, file/database reading, writes, deletion, network, or root helper. Reports only success/errno and uid/euid. errno 1/13 indicates permission denial; 2 indicates absent path, not necessarily denial. Other errors must be interpreted as errors, not automatically permissions.

A successful directory-open is a necessary but insufficient indication of functional access: AppGroup-root access does not establish Notes group or NoteStore.sqlite readability; legacy Notes might not exist. No personal content is accessed or displayed. C success does not mean management/export works.

## Test

1. Install ONLY C via the same TrollStore 2.1 on the same phone; do not replace A/B or the manager. Open C and leave it foreground for at least 10 seconds, then relaunch once.
2. If it stays open, tap the directory test once. Return only startup outcome, uid/euid and the three result lines; no private data.
3. If it exits, do not try another guessed package. Compare actual installed entitlements and crash reason. In TrollStore app Details, inspect the Entitlements view for A, B, C (check for complete raw key/type values; a capability summary alone is insufficient). If unavailable, use an already-working file tool to copy ONLY each installed app executable from its bundle, not Documents/Library/data containers; on an existing Mac/Linux with ldid run `ldid -e StartupProbe > installed-entitlements.plist`. Compare container-required value AND type, no-sandbox/no-container, and any installer-added entitlements. Never assume the packaged IPA is the installed binary. A relevant crash report exception/termination reason can separate AMFI/code-signing from runtime failure; redact identifiers and private paths.

Only after C device success should the manager's data-container assumptions and Notes-specific read permissions be addressed. Uncontainerized HOME changes require review before migration; blindly applying this plist to the manager is explicitly out of scope until verified.
