# Files DualPane 0.6.0

Target: RootHide, Files on iOS 16.6 build 20G75 only. Package ID unchanged. Cross-pane copy/move is **not yet implemented**. The user confirmed 0.4 dual panes; neither 0.5 nor 0.6 has been declared device-verified.

## Defaults

- First normal scene connection in each Files process schedules one automatic presentation after the root/scene is ready (up to 10 seconds of bounded readiness retries). Closing is respected for the rest of that process. Returning from background, preview or viewDidAppear never rearms automatic presentation. The manual “双窗格” entry remains.
- URL / user-activity / shortcut cold launches and an existing modal/preview skip automatic presentation. Later openURLContexts / continueUserActivity events cancel a pending automatic attempt. Unsupported scene ABI falls back to the manual entry; startup timeout does not hijack a later screen.
- Both panes are visible side by side, also on narrow phones. “左栏 / 右栏” remain user choices. Rotation no longer automatically hides a pane.
- Each independent pane requests list view once after its native collection is ready. It invokes DOCFullDocumentManagerViewController.performViewAsList: (ABI v@:@), evidenced by the runtime report and public header. Files resolves its own list enum. Although setDisplayMode: (v@:q) is evidenced, its numeric enum is not: no guessed integer is used. accessibilityIsInListMode (B@:) checks the immediate result. Unavailable/unconfirmed list setup shows a navigation prompt and preserves native layout; use that pane's native view menu.
- All state remains in the existing copied configuration / unique transient namespace. Original Files sorting/layout defaults are not directly modified. Native private implementation details still need device validation.

## Smaller icons, filenames

0.5 only set maximumSize=24 on UIListContentConfiguration. The legacy branch changed UILabels but did not resize native thumbnail views, explaining an uncovered large-icon path (source diagnosis, not a device measurement).

0.6 uses 22×22pt for public list content. In confirmed plugin list rows, it also targets the evidenced DOCFittingImageView hierarchy (including DOCThumbnailFittingImageView), adjusting its existing standalone width/height constraints to 22pt. Frame-based thumbnails without those constraints have only their icon bounds reduced, with original bounds saved for restoration. No whole-UI transform, system Files root modification or arbitrary image-view search is used. Saved styling is restored outside plugin lists. Unknown native thumbnail classes are left untouched.

Three-line filename configuration and fitting-height handling remain. Legacy label fallback from 0.5 remains; it is not proof that every native cell/large-text layout will render three lines. No screenshot or true-device visual claim is made.

## One optional targeted capture for the missing cross-pane bridge

Existing reports establish native action/selection callbacks, not a proven selection-to-provider-URL transfer contract. No unsafe Swift offsets, unknown getter execution or simulated cross-pane actions are added.

1. Use temporary test files. In the left pane, select two **visible** files; keep both selected and on screen.
2. Navigate the right pane to the intended target directory.
3. Tap “桥接采集”, then “采集并由我选择分享” once. Share the generated text manually. This one snapshot is only to finish the cross-pane bridge, not another general runtime dump. Do not repeat after relaunch.

Default is off. The snapshot collects both panes together, at most 16 visible selections per pane / 32 anonymous objects / 96 filtered method signatures per object. It reads UIKit selection and only evidenced getters: Full.currentItemCollectionViewController, Full.hierarchyController, hierarchy.lastLocation, DOCConcreteLocation.node, and DOCThumbnailFittingImageView.node/url. Node/provider URL accessors are **discovered as metadata, not invoked**. It reports classes, relevant selector signatures, anonymous relation IDs, and booleans for thumbnail URL object presence / file-URL type. These booleans do not prove permission, download completion or readability. Offscreen/unsupported selected cells are reported as missing rather than guessed. Directory URL getter invocation is explicitly false.

No names, paths, URL strings, account values, file contents or memory addresses are exported. No file access, automatic network request, disk log, pasteboard write or background capture. The system share sheet runs only on explicit confirmation. The button disables for the process; no persistent usage/log flag is stored, so the once-only authorization also relies on not repeating after a restart.

## Safety and verification

Existing native rename/create/select/delete confirmation and coordinated QuickLook code are retained. Closing removes only plugin children, configuration states and owned references; no shared observer is stopped, foreign token removed or original Files hierarchy transplanted. Uninstall removes the tweak; no plugin filesystem logs or user-file modifications are introduced.

CI runs source safety checks, the production transient-state wrapper host fixture and coordinated-preview/scope fixture using temporary files, then compiles arm64 + arm64e with RootHide Theos and verifies deb identity/version/architectures. Source checks are not UIKit UI tests. This environment does not read user device files or validate real Files launches, iCloud/provider behavior, visual size or runtime leaks.
