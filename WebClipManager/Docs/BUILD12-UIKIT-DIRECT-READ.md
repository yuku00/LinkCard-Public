# Build12: direct-read UIKit business interface

## Decision and evidence

This build is a substantive alternative to the blocked container-parent helper path, not another entitlement probe. It does **not** claim that sandboxed spawn is universally impossible, nor that the previous SwiftUI crash has been diagnosed. No verified applicable process-exec exception was found in the reviewed sources; no speculative exception, persona override or UID change is added.

- Santander fixed revision `8ea2bec1a54b94517c65e3f44f70627481922813`, `Santander/Other/RootHelper.swift`: `contents`/`perform` call `spawn`; the full caller sets persona 99 with OVERRIDE, UID/GID 0 before `posix_spawn`, and consumes stdout/stderr then waits. Its `entitlements-TS.plist` specifies no-container=true/container-required=false and persona-mgmt. This is **not evidence that our container parent can spawn an unsandboxed mobile helper**.
- Santander same revision, `Santander/SceneDelegate.swift:36–76`: owns a UIWindowScene window, assigns a UIKit navigation root, retains the window and calls makeKeyAndVisible. This is the architectural precedent used here (MIT license retained), not a claim of device verification for this app.
- TrollStore revision `88424f683b2a08f34a3f88985f790f97d84ce1df`, `Shared/TSUtil.m:99+` also uses persona 99 / UID/GID 0 in spawnRoot. Its UI entitlement set differs from ours; copying the child command alone cannot reproduce its prerequisites.
- TrollStore same revision, `RootHelper/uicache.m:45–82` distinguishes no-container=true / container-required=false and supplies noncontainer HOME. The app does not overwrite HOME, CFFIXED_USER_HOME or TMPDIR.

The main signature restores the exact eight-key build9 noncontainer profile; it adds **no new entitlement**. Build9 had an observed successful directory-open path; that is narrower than a successful full scan and not proof this build works on a device.

## Implemented paths

1. UIApplicationMain → StartupDelegate scene configuration → BusinessSceneDelegate → BusinessTabs → two UIKit navigation/table controllers. The production root never constructs the old diagnostic launcher or a SwiftUI hosting controller.
2. Confirmed WebClips read → Repository.scan → ReadAccess.entries / real POSIX directory reads → Info.plist parsing → visible rows. The unconditional device-root helper diversion is removed. Actual errors are failures, not empty successes.
3. Select / search / backup → existing Repository.backup → private export staging → on-demand UIDocumentPicker copy. Partial backup is refused instead of being advertised as complete.
4. Confirmed Notes read → existing AppleNotesStore.locate/read → readonly SQLite source + in-memory backup → existing gzip/protobuf decoder → visible rows and skipped counts → selected TXT/Markdown files → same UIKit export path. There is no helper or source database write command.
5. Export staging uses mkdtemp (0700), exclusive no-follow files (0600), and removes only paths it created. No generic /var/mobile/Documents write or shared-directory purge. Interrupted exports may leave an app-prefixed private temporary directory for OS cleanup; no automatic scan of old private exports is performed.
6. No automatic personal-data read on launch; no deletion UI. Repository deletion remains explicitly disabled.

The old SwiftUI source/test coverage is retained for reference but is not the production root. Its old diagnostic launcher is unreachable from the new business UI. Build11 helper source remains for transport regression coverage, but the executable is neither packaged nor called by Repository.

## Validation contract

- `Tools/test_build12_policy.py`: checks exact profile, production scene root, actual repository route, Notes call, and owned export files.
- `BusinessIntegrationTests`: real application scene/root launch; complete UIKit table scan/selection/backup with synthetic WebClips; real synthetic Notes AppGroup discovery, WAL snapshot/decode/table/TXT/MD export; missing-directory failure; private staging permissions/traversal/cleanup.
- Existing repository, file-access, Notes decoder/WAL/source-unchanged, runtime redaction and legacy UI isolation tests remain.
- Production C helper transport regression is retained, including simulated spawn EPERM returning unavailable child status instead of false exit=0. This does not solve a device sandbox refusal and is not used as its proof.
- Workflow selects an installed iOS16 simulator if present, otherwise records the actual installed runtime. Deployment target remains 16.0. A newer simulator passing is **not** iOS16.6/TrollStore permission verification.
- Device IPA verification checks arm64/iPhoneOS/minimum OS, dependency paths, XML/DER entitlement equality and code-directory page/entitlement hashes; no helper executable may be present.

## Still unverified / not implemented

No new iPhone14/iOS16.6/TrollStore2.1 launch, full WebClips listing, installed entitlement behavior, or real Notes export has been observed for this build. It must not be labeled a verified device fix. File-provider save UI behavior on that noncontainer device remains unverified. No deletion, Notes unlocking, attachment download, rich-text/table reconstruction, or backup restore. This compact UIKit path does not expose the legacy text-file import and special duplicate/full-screen filter controls; basic search/selection/readonly backup and direct Notes export are implemented.
