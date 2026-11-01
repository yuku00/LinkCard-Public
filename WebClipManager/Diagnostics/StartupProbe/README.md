# Objective-C startup probes — diagnostic only

Reported device: iPhone14, iOS16.6, TrollStore2.1. Build3 Swift UIKit entry still exits immediately; no ips supplied. Device reproduction is unavailable to CI. Do not claim a fix from successful compilation.

A and B are independent bundle IDs, not updates to the manager. Both use the exact same compiled Objective-C UIKit binary. Only bundle label/ID/icon/variant and signing entitlements differ. UI shows variant, launch success, system version. No Swift/SwiftUI, task, Notes, WebClip scan, file logging, network, or private-data access. B requests only no-sandbox; A's input signature is an empty dictionary. No platform-application or guessed permissions.

## Official evidence checked before building

- https://github.com/opa334/TrollStore/blob/2.1/README.md#unsandboxing explicitly lists no-sandbox=true and recommends it when a data container is still wanted. platform-application is described as potentially needed with side effects, not mandatory for a minimal UIKit launch.
- https://github.com/opa334/TrollStore/blob/2.1/RootHelper/main.m lines608–610 and670–693: the installer adds container-required=<bundleID> for the new CoreTrust bypass when appropriate, but skips this injection when no-container or no-sandbox is true. This is installer logic, not evidence that our input IPA must manually add the key. Therefore installed entitlements may differ from the input artifact, especially A. Package A/B checks describe the supplied IPAs, not a post-install extraction.
- Build3 main.swift defers SwiftUI construction but its binary still links Swift/SwiftUI; prior logs confirm Swift compilation and no-sandbox-only entitlement. Build3 therefore did not eliminate pre-main Swift linkage. Its failure does not establish Swift as the cause.

No evidence currently proves a required Info.plist container attribute is missing. Do not confuse LaunchServices registration state, input Info.plist, and installer-injected signature entitlements. No changes to the manager or other apps are made.

## Minimal human feedback loop

Install/open A with TrollStore, observe 5 seconds; then install/open B and observe 5 seconds. Record only whether the success page remains visible. No settings refresh, upgrades, deletion or privacy access required.

| A | B | Interpretation (not proof) |
|---|---|---|
| success | success | Minimal UIKit and both signing paths can launch; narrow next investigation to original binary/dependencies/registration/init. |
| success | exits | Prioritize no-sandbox-related signing/container/registration differences; do not add broad permissions. |
| exits | success | Prioritize sandbox/container handling specific to A, not Swift. |
| exits | exits | Failure persists without Swift; prioritize shared packaging/install/launch validation. |

Unexpected install error is a separate result, not an app crash. Neither successful probe alone proves the original application's root cause. CI checks direct dynamic dependencies and undefined imports for Swift, validates exact signed input entitlements and outputs SHA256; UIKit's internal system implementation is outside the claim.
