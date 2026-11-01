# Build11 container / fixed read helper candidate

## Pinned source evidence

Santander MIT revision `8ea2bec1a54b94517c65e3f44f70627481922813`:
- https://github.com/NSAntoine/Santander/blob/8ea2bec1a54b94517c65e3f44f70627481922813/RootHelper/main.swift
- https://github.com/NSAntoine/Santander/blob/8ea2bec1a54b94517c65e3f44f70627481922813/Santander/Other/RootHelper.swift
- https://github.com/NSAntoine/Santander/blob/8ea2bec1a54b94517c65e3f44f70627481922813/Makefile
- https://github.com/NSAntoine/Santander/blob/8ea2bec1a54b94517c65e3f44f70627481922813/entitlements-TS.plist
- https://github.com/NSAntoine/Santander/blob/8ea2bec1a54b94517c65e3f44f70627481922813/LICENSE.md

Upstream main validates its parent executable name, sets uid/gid 0, and dispatches generic filesystem commands. The caller uses bundled executable resolution, posix_spawn, stdout/stderr pipes, persona 99 override and uid/gid 0. Makefile builds a separate executable, embeds it, signs app/helper separately, chmods helper 6755. This proves an independent executable pattern, NOT that root is necessary for fixed read operations. Its spawn code credits Pogo; none of that code is copied. This candidate is newly implemented, conservatively retains Santander MIT attribution, uses mode 0755, no setuid/setgid/persona, no generic path commands. No GPL/private implementation or TrollStore BSD uicache implementation is copied.

Historical device evidence says build9/10 fixed directory open succeeded as uid/euid 501; this is justification to try same-UID helper, not proof it inherits the required sandbox policy. The helper's separate noncontainer/no-sandbox signature must still be verified on device. If it returns EPERM, do not silently escalate or claim success.

## Implemented

- Main application restores build8's seven entitlements including string container-required; OS HOME/TMPDIR remain untouched. Original interface and explicit open-main button retained.
- Version text comes from CFBundleVersion. Container-only stage file Library/WCM-stages.log retains bounded fixed markers and numeric errno/exit across launches; no names, URLs, Notes, or raw protocol data are logged.
- WebClipReadHelper is Foundation-only Objective-C, no SwiftUI. Only exact `webclip-list`, no extra args. Parent must resolve to sibling WebClipManager. No shell, arbitrary paths, deletion or write command.
- Directory traversal starts at `/` and uses fixed `/private/var/mobile/Library/WebClips` components with descriptor-relative openat/O_NOFOLLOW. Entry and file opens are descriptor-relative, regular-file checks and bounded reads; Info.plist 2 MiB; optional icons 256 KiB each; up to 1000 clips, 4096 visited entries, total JSON 8 MiB. Overflow fails closed, not silently complete.
- UI scan calls Repository actor -> C posix_spawn transport with nonblocking pipe, no inherited environment secrets, 8-second deadline, output bound, exit/signal checking and child reaping. Failures are application errors, not process exit. Swift validates protocol version, counts, fields and identifiers.
- Notes device loading is explicitly unavailable, no direct database fallback; existing synthetic Notes decoder and text import/export retained. Full device directory backup explicitly unavailable in this candidate. Delete remains disabled.
- Main/helper are built and signed separately; IPA inspection validates both actual XML/DER entitlement blobs, CodeDirectory page and entitlement hashes, arm64/iOS16 Mach-O and executable archive modes.

## Test boundaries

`Tools/test_helper_transport.py` compiles the real C client and drives synthetic child success, exit failure, SIGKILL, timeout, oversized output, invalid commands and symlink executable rejection. `HelperProtocolTests` validates decoded JSON and fail-closed behavior. Existing StartupIsolationTests drives UIKit open button into complete RootView and asserts no scan. Existing repository/Notes data tests use synthetic fixtures. No real bookmarks or Notes are used in tests or uploaded.

The iSH local ctypes/spawn transport test stalled after compilation and was stopped by tool timeout; do not represent it as passing locally. Native macOS CI is the authoritative process-test environment. Simulator UI success cannot prove TrollStore/iOS16.6 launch or cross-sandbox access.

## Minimum device acceptance (not performed by builder)

1. Install candidate manually; open UIKit homepage, then tap open main interface. Confirm full interface remains open. Do not initially read Notes or invoke deletion.
2. Tap scan bookmarks once. Verify a real listing or the explicit errno/exit error. No automatic scan occurs on launch.
3. If it fails, relaunch and copy fixed stage log. Do not send real bookmark data, databases, or private note text.

Only after successful device WebClips verification should Notes helper protocol be implemented. No release or device installation is performed by this build workflow.
