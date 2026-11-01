# Build6: WebClips read-access candidate

## Established baseline

User confirmed build5 starts, opens SwiftUI and survives manual refresh on iPhone14 / iOS 16.6 / TrollStore 2.1. Reading WebClips fails. This is NOT an unresolved launch crash. Preserve the UIKit entry, deferred SwiftUI, manual-only reads, platform identity and string-valued container configuration. Startup page label changes only; the historical startup-build5.log filename is retained (each line records the actual build).

## Evidence and limits

- TrollStore upstream README, https://github.com/opa334/TrollStore#unsandboxing : no-sandbox with platform-application can still need storage entitlements; AppDataContainers is documented for the app's own container. Unsandboxing does not prove unrestricted MAC/TCC or POSIX access.
- Santander source at commit 8ea2bec1a54b94517c65e3f44f70627481922813, `entitlements-TS.plist`: includes `com.apple.private.security.storage.Safari = true`. https://github.com/NSAntoine/Santander/blob/8ea2bec1a54b94517c65e3f44f70627481922813/entitlements-TS.plist
- Audited TrollScript 3.0.5 executable XML/DER signatures: main executable has Safari storage true among 269 entitlements; RootHelper also has Safari storage true. No whole-profile copy.
- Filza official public TrollStore 4.0.2 NoURLScheme IPA, https://tigisoftware.com/download/Filza_NoURLScheme_4.0.2.ipa ; SHA256 df4092ba3c5391555fc7618fdd9a87cc3c32f6ca1d3c03e464e99be19877c1a3. Its main binary does NOT have Safari storage; helper uses `com.apple.private.security.storage-exempt.heritable`. It therefore is not proof that Safari storage is required or sufficient, and its much broader helper configuration is not copied.
- No authoritative iOS16.6 policy mapping proving WebClips -> Safari storage was found. Safari is the narrowest evidence-backed candidate among the inspected storage profiles, NOT an established root cause. Do not report successful access until device feedback.
- Existing `Repository.check` calls NSURL resourceValues before reading, so the original error could be a metadata preflight denial. Build6 uses lstat + read-only open/fstat and fdopendir/readdir. lstat itself can still be denied; the separate open probes expose that distinction.
- `/var` is normally a system alias of `/private/var`; diagnostics measure both, do not assume. Production rejects final symlinks, while fixed-path diagnostic opens follow system aliases. Probes do not enumerate contents. No arbitrary resolved paths are exported.

## Exact change scope

Keep all six build5 entitlements unchanged; add only `com.apple.private.security.storage.Safari = true` (seven total). No persona/root helper, storage-exempt, wildcard, rootless entitlement, chmod/chown, or mutation of WebClips/Notes. Storage entitlement itself is not read-only scoped; application operations remain read-only. No changes to Notes implementation or deletion behavior (`deletionEnabled=false`). Selector presence remains metadata only.

Schema 2 adds actual build, latest manual-read fileAccess and readFailure. Fixed-path probes include uid/euid/gid/egid, open result/errno, lstat and realpath errno, symlink flag, fstat errno, mode and owner. NSError serialization whitelists domain, numeric code, nested POSIX code and operation/category. No descriptions, userInfo, bookmark names, URLs, arbitrary child paths or contents. ENOENT/ENOTDIR/ELOOP/EACCES/EPERM remain distinct; EACCES/EPERM alone cannot distinguish DAC/POSIX from MAC/sandbox.

## Feedback loop

Local regression gate was run RED before the change:
`python3 Tools/test_webclips_access.py` -> `AssertionError: Missing reviewed Safari storage candidate`.
This is only a packaging/preflight regression gate, not a reproduction of device MAC policy. No agent-runnable iOS16.6 device seam is available. New XCTest cases cover real POSIX directory opens, missing directories, final symlink rejection, nested errors/redaction and fixed-path diagnostic sanitization. Existing Repository/Notes/startup tests stay enabled in CI. Synthetic tests never read private Notes or shared archives.

## Minimum device test

1. Install build6 yourself with TrollStore; launch and open the unchanged SwiftUI interface.
2. Tap refresh once. Check whether it is readable, partial or failed; do not test deletion or Notes.
3. Open Diagnostics and export JSON. Report whether content appears and send only the sanitized JSON. Confirm build=6 and deletionEnabled=false. If failed, fileAccess/openErrno and readFailure will localize the next investigation; no automatic elevation is performed.

Build artifact verification checks CFBundleVersion=6, arm64 iPhoneOS/minimum iOS16, signed XML and DER exact seven-entitlement policy and CodeDirectory hashes. Fakesigning/static validation is not CoreTrust/device-read verification.
