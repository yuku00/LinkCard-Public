# Files DualPane 0.5.0

RootHide / arm64 + arm64e / Files / iOS 16.6 **20G75 only**. Keeps the two native Split factories verified by the user in 0.4.0; no custom file list and no new collection round.

## Use

1. Open Files → 双窗格. 并排 / 左栏 / 右栏 keep independent native navigation stacks alive.
2. Tap 左栏 · 操作 or 右栏 · 操作. 选择 / 完成, 全选 and 取消选择 operate that pane's real native selection. Navigate into a directory first; source/sidebar pages have no file actions.
3. Select items, then use 重命名, 属性 / 完整名称, 预览 or 删除…. 新建文件夹 uses the current native directory. Unsupported native actions are disabled rather than pretending to run. Native menus are restored.
4. Delete entrypoints performDelete:, performDeleteNow: and delete: gain a pane-scoped explicit warning, including permanent loss. The native provider continues to determine trash versus permanent deletion. Other provider-specific native routes are not a plugin-enforced sandbox.
5. Opening document URL callbacks presents QuickLook. Security scopes are held through preview destruction. A background NSFileCoordinator read checks reachability and iCloud download state; errors are displayed, not reported as success. No URL is synthesized from a provider identifier and no private path bypass is used. Scope acquisition may return false for host-accessible files; the coordinated read determines access. Providers may still require their native download flow.
6. Close returns to original Files. Existing native preferences/history are not erased.

## Long names

Actual native file-list cells are discovered through the verified willDisplayCell callback. Changes apply only under this plugin's panes and only to full-width list rows, not sidebar or grid views. Public UIListContentConfiguration uses three lines and a 24pt maximum image. Legacy cells use their actual visible UILabel hierarchy, selecting the top filename-sized label; no Swift offsets or arbitrary KVC. Preferred self-sizing attributes use native Auto Layout measurements, capped at 120pt. Cells leaving the scope restore changed style settings. No transform scaling.

This is an improvement, **not unlimited filename display**: native fixed-height layouts may not adopt preferred sizing, and legacy cells do not expose a guaranteed icon configuration. Their icon size remains native. Half-screen width and very long names can still truncate. Native 属性 / 完整名称 and full-width pane modes are available. Device rendering of the new changes has not been certified by the earlier 0.4.0 confirmation.

## Exact delivery boundary

**Cross-pane copy/move is not implemented in 0.5.0.** The existing runtime reports expose currentItemCollectionViewController, native selection actions and DOCConcreteLocation.node, but no verified selected-node → accessible URL mapping or consistent current-folder scope acquisition contract for these collection controllers. The Swift diffable cache/selection ivars have no safe Objective-C accessor evidence. This release does not guess offsets, arbitrary KVC, index-to-item mapping, pasteboard completion timing, or provider paths. Consequently it also does not claim transfer conflict handling, transfer cancellation, copy verification, or safe source removal. No fake transfer button is shown.

Rename, folder creation, properties and mutations remain **native Files/provider operations**, not a new plugin filesystem engine. Native naming validation, conflict prompts, download handling and errors remain authoritative. Plugin-specific skip/keep-both/no-overwrite policy is not imposed on the restored native menus. A full MT-style safety/transfer engine is still an explicit missing feature, not completed scope. ZIP, text editing, APK and root filesystem browsing are excluded.

## Privacy / teardown

Production links Entry.m + DualPane.m (including NativeActions.inc and ScopedPreview.inc). No recorder, log, network request, document-content telemetry, automatic file mutation, or fixture against existing user files. Two UUID-namespaced in-memory state stores remain independent. Native data sources/action managers remain independent. No new global item/index/selection cache is introduced. Closing clears owned state and children; shared observers are never stopped. QuickLook ownership releases only scopes successfully acquired by this adapter. Uninstall and restart Files to unload hooks.

## Verification

CI runs static factory/action/scope checks; compiles and executes the actual production state wrapper code on macOS; compiles and executes the actual preview checker/ownership class using temporary-directory fixture files, missing-file failure, separate preview lists and scope release. QuickLook's UIKit superclass is stubbed in the host ownership test, not claimed as a device UI test. The build verifies both Mach-O slices, RootHide package metadata and SHA-256.

There is no file-transfer fixture test because no transfer engine is shipped. Native selection/cell rendering/provider mutation behavior cannot be certified by host tests. No user data is used for testing.
