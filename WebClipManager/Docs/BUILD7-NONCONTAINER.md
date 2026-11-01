# Build 7: coherent non-container candidate (not device verified)

## Evidence and uncertainty

The prior device pattern is successful lstat/realpath but EPERM from an actual O_RDONLY directory open of the WebClips target, not only its parents; Notes AppGroup discovery was also permission denied. This does not mean ENOENT, and uid 501 does not prove root is necessary. Opening a directory for reading is not the same as traversing it. A POSIX error alone does not establish which MAC/Seatbelt/data-protection policy denied access.

Ranked hypotheses: (1) the explicit container registration still applies a restrictive profile despite no-sandbox, (2) installed/self entitlements differ from the IPA, (3) another MAC/data-protection rule remains. Hypotheses are not device findings. Existing artifacts cannot prove current process sandbox state.

## Minimal consistent mode change

Keep platform-application, the app's own application-identifier, no-sandbox and the existing three storage entitlements. Change container-required from the app-ID string to boolean false; add no-container=true and app-sandbox=false. Exactly nine keys, checked for both values and types. No root helper, persona, manager, broad filesystem exception or new storage exemption. This is a limited coherent candidate, not a claim that all nine keys are independently necessary.

TrollStore 2.1's uicache explicitly returns non-containerized for no-container=true or container-required=false, but uses strings as explicit container IDs. Its non-container HOME/CFFIXED_USER_HOME are /var/mobile and TMPDIR is /var/tmp:
https://github.com/opa334/TrollStore/blob/2.1/RootHelper/uicache.m#L45-L81
Installer entitlement handling:
https://github.com/opa334/TrollStore/blob/2.1/RootHelper/main.m#L609-L704
Santander's source uses platform + false/no-container + app-sandbox=false (alongside many other privileges; those were not copied):
https://github.com/NSAntoine/Santander/blob/main/entitlements-TS.plist
Local prior TrollScript 3.0.5 signature audit found the same mode plus no-sandbox. Its 269 permissions and helper do not establish which are needed. Source URLs above were re-read over verified TLS for this change.

## Application data isolation

On device the app root is /private/var/mobile/Library/Application Support/org.example.WebClipManager. Only the dedicated root and descendants may be created or chmodded; path walking uses openat/O_NOFOLLOW, checks owner, and applies 0700. Documents, Library/Preferences, Library/Caches and tmp are inside it. HOME, CFFIXED_USER_HOME and TMPDIR are set before UIApplicationMain; Foundation home/Documents/temp are then compared to the intended locations. Simulator retains its app-exclusive container.

Application code does not use UserDefaults/@AppStorage. There is no migration or enumeration of /var/mobile/Documents, old containers, or other application preferences. A Foundation path mismatch disables application log disk writes, importers, and all fileExporter presentation. The read-only interface and selectable in-memory diagnostic remain available. No unverified shared path is a fallback. System framework-internal storage cannot be proven from source review alone; the diagnostic exposes actual Foundation path-match booleans.

Export payloads remain memory-backed FileDocuments; user explicitly chooses the destination. Startup-log sharing exports only current-process allowlisted stage text, never an on-disk file URL or arbitrary contents. Logs reject final symlinks/hard links, have bounded size, and are only under the owned root. No other app's files are exported as logs. Notes bodies remain in memory and are not part of diagnostics. Deletion remains disabled. UIKit entry and manual transition to SwiftUI/read buttons are preserved.

## Installed-process evidence

Schema 3 calls the real C SecTaskCreateFromSelf/SecTaskCopyValueForEntitlement APIs through correctly typed dlsym function pointers (not an invented Objective-C class). Only nine allowlisted keys are queried, with explicit type-aware match/mismatch/unknown comparison. Unknown APIs/errors are not reported as successful no-sandbox. Non-own identity strings are redacted.

sandbox_check queries file-read-data and file-read-metadata for three fixed system paths; results/errno are operation-specific, not a global unsandboxed verdict. Actual open/lstat/realpath metadata also includes AppGroup's fixed parent without listing it. A Notes user-triggered read records only state and sanitized NSError code/domain/underlying POSIX, never titles, bodies, counts, container IDs or error descriptions. Thus installed signature mismatch, Seatbelt denial, and actual filesystem access can be compared in one report.

## Feedback loop and limits

`python3 Tools/test_build7_policy.py` first failed on build6's explicit-container string, then passes after the change. This is a policy/configuration regression, NOT a reproduction of iOS Seatbelt execution. No device access is available to make the actual EPERM test green; user-triggered exact-target read + new runtime evidence is the remaining validation loop.

New XCTest coverage exercises owned-path prefix/traversal/symlink rejection, current-process entitlement capture's whitelist/unknown behavior, and diagnostic/log privacy. Existing synthetic read-only/Notes/DER tests remain. Workflow runs checks, XCTest, arm64 device compilation and actual IPA XML/DER + CodeDirectory hashes verification. Public upload is explicit source allowlist only; no device diagnostic or Notes content is included.

## One device check

Install the main build7 IPA with TrollStore, enter SwiftUI, refresh WebClips once, then tap Read Apple Notes and confirm its read-only action once. Return to Diagnostics, update it and export only the sanitized JSON. If dedicated paths fail validation, use the selectable diagnostic text instead. Do not send Notes exports, screenshots of Notes contents, or databases. Success is not claimed until this device feedback exists.
