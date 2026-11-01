# build5: explicit-container candidate (not device-verified)

## Facts and diagnostic boundary

The user confirmed the same-device working TrollScript is 3.0.5, the analyzed release (SHA-256 e1751eb6d8f9c155d115bbbaaa9925a7ff9474963bea509b9be586ded7b16229). The old audit's request to ask the version again is superseded. iPhone 14 / iOS 16.6 / TrollStore 2.1 / Bootstrap; B injection disabled. Empty-entitlement ObjC A launches; no-sandbox-only B and container-required=false-only C exit immediately. No device is connected to this build environment. There is no agent-runnable regression test for this exact pre-main termination. Source/signature tests below do NOT prove launch fixed. The user has requested one bounded candidate rather than another research/probe loop.

Ranked hypotheses: (1) incomplete identity/container profile changes TrollStore signing/registration (candidate tests this combined profile, not each key's causality); (2) installed CoreTrust/registration differs from distributable signature (not observable here); (3) SwiftUI/dyld issue specific to main app (does not explain ObjC B/C, but staged homepage remains useful). No root cause is claimed.

## One chosen profile, six keys

| Key | Value | Reason |
| --- | --- | --- |
| platform-application | true | Present in working TrollScript and Santander TS profile; absent in failing B/C. Platform status is not uid 0. |
| application-identifier | org.example.WebClipManager | Own identity, not TrollScript's. Nonempty entitlement dictionaries do not receive the empty-dictionary fallback identity in TS. |
| com.apple.private.security.container-required | org.example.WebClipManager (string) | Explicit own data container. TS recognizes a string as a container identifier. Avoids HOME=/var/mobile and TMPDIR=/var/tmp non-container mode. |
| com.apple.private.security.no-sandbox | true | Required candidate capability for manual cross-sandbox WebClips reads; paired with explicit container instead of relying on TS's skipped default insertion. Broad capability, not a read-only enforcement mechanism. |
| com.apple.private.security.storage.AppDataContainers | true | Limited storage class for existing manually requested app-container reads; present in TrollScript and Santander. Does not prove all shared-group reads will work. |
| com.apple.private.security.storage.Notes | true | Existing separately confirmed Notes read feature, from Santander TS profile; not asserted to be present in TrollScript or necessary for startup. |

No no-container, container-required=false, app-sandbox=false, root-path read/write exception, storage-exempt.heritable, container-manager, sandbox-manager, AppBundles, JIT, debugger, get-task-allow, persona or root helper is included. This is the smallest selected internally consistent profile for this candidate, not a proof that each of six keys is individually necessary. No further permission permutations are queued.

## Sources and what they actually establish

- TrollStore 2.1 RootHelper/main.m lines 609–704: https://github.com/opa334/TrollStore/blob/2.1/RootHelper/main.m#L609-L704 . Explicit container strings are kept; no-sandbox stops default string insertion. Existing nonempty entitlements skip the no-entitlements identity fallback.
- TrollStore 2.1 RootHelper/uicache.m lines 45–81: https://github.com/opa334/TrollStore/blob/2.1/RootHelper/uicache.m#L45-L81 . A string selects its container identifier; false/no-container selects non-container HOME/TMPDIR. We deliberately use the former.
- TrollScript 3.0.5 release: https://github.com/dompling/TrollScript-Release/releases/tag/latest . Parsed actual XML and DER of widgetExtension both contain platform=true, its own application-identifier, no-sandbox=true and container-required=<its bundle ID>. This is a signed-distribution precedent for the identity/container quartet, NOT proof the widget itself ran or proof that a reduced main-app profile will launch. The main app is the user's positive launch control but uses a much larger non-container profile. Its private implementation is not public source and was not copied.
- Santander: https://github.com/NSAntoine/Santander/blob/main/entitlements-TS.plist and https://github.com/NSAntoine/Santander/blob/main/Makefile . Supports platform status and named storage entitlements as open-source precedents. Santander's non-container/no-no-sandbox profile is NOT the exact profile used here; its broad storage/root/debug/persona privileges and helper were not copied. Only configuration facts were consulted.

## Storage and feature safety

All Sources were searched for Documents, temporaryDirectory, NSTemporaryDirectory, createDirectory, removeItem, export and backup calls. Only StartupLog directly creates a local directory/file. It now writes only <own container>/Documents/WebClipManager/startup-build5.log. The resolver rejects /var/mobile/Documents, /var/tmp, malformed container paths and existing symlink redirection; unavailable log paths fail closed without stopping the app. This is defensive validation, not a claim of race-proof filesystem access against a hostile local process.

UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace are false. Export shares only the validated log file, never the Documents root. There is no cleanup or migration of old logs/user files. FileDocument exports remain user-selected and in-memory; Notes database backup remains read-only source to in-memory SQLite. No explicit temp directory writer exists. Existing WebClips backup starts only from its fixed repository root, not HOME/Documents. UIKit homepage and main view do not auto-scan; refresh is manual. Notes still requires a separate confirmation. Deletion remains unavailable with no direct removal fallback. Logs retain fixed stages, OS/build/time only, no titles, paths, URLs, counts or raw error descriptions.

## Tests, packaging and scope

Tools/entitlement_policy.py defines a closed six-key/value/type policy shared by static source checks and actual IPA inspection. Negative self-tests reject no-sandbox-only, extra debugger permission, false container and impersonated identity. DER decoder rejects malformed/trailing input. New policy was run against the original one-key file and rejected it before the fix. Tools/verify_ipa.py requires build=5, own bundle ID, arm64/iPhoneOS/minimum iOS 16.0, no missing @rpath embedded dependencies, actual XML/DER equality to the policy, and valid SHA-1/SHA-256 code-page and entitlement hashes. XCTest adds rejection of global Documents/tmp and acceptance of own dedicated log path; existing no-auto-read startup tests remain.

One manual workflow builds/tests/packages. Upload scope is only WebClipManager/ and .github/workflows/webclip-manager-build.yml in yuku00/LinkCard-Public, using latest parent/base_tree and force=false, preserving unrelated paths. Existing token-variable and unauthenticated signed-artifact-redirect helpers are reused. No installation, release publication or other project changes.

## One minimal device check after successful build

Open build5 -> confirm UIKit startup page -> tap Open SwiftUI (no read) -> tap refresh once. Report the last visible stage and whether refresh returns a list or a permission error. Do not test deletion. This single path distinguishes pre-main/launch, UI transition and manual read failure. Actual iOS 16.6 launch, installed entitlements/CoreTrust, cross-sandbox access and Notes export remain unverified until device observation; simulator XCTest is not a substitute.
