# Files DualPane 0.7.0

Target: Files on iOS 16.6 build 20G75, RootHide, arm64/arm64e.

## UI

Removed both top operation strips and the bridge-report capture entry. Native navigation, context menus, selection and QuickLook remain. Default layout remains side-by-side native lists. Public small-title navigation policy is applied only to plugin-created navigators. A bottom native menu for each pane contains only cross-pane copy/move and home settings. The local status label shows the destination and real completion counts/errors; no operation data is logged.

Native list cells use 20pt icons, 13pt primary and 11pt secondary base fonts scaled with Dynamic Type. Self-sizing rows request `max(44, 2 * primaryLineHeight + secondaryLineHeight + 8)`. If Files imposes a fixed height, names fall back to one line when two do not fit. Names never exceed two lines. Original styles are restored outside the plugin list scope; no global transform or private Swift layout ivars are used. Long names remain available through native Get Info.

## Transfer support and limits

The received snapshot establishes `full.hierarchyController.lastLocation -> DOCConcreteLocation.node -> FPItem.fileURL/nodeURL`. Selection always comes from the actual collection's public selected index paths. The device's Swift generic data source does NOT expose an Objective-C item getter. `DiffableBridge.swift` therefore adds a local Swift protocol conformance to the public generic UIKit class, preserving its real Section/Item specialization and calling public `itemIdentifier(for:)`. An ABI-checked NSObject facade passes the returned FPItem back to Objective-C. This supports offscreen selected paths without reflection, private Swift storage or force-casting the wrapper to the unrelated Objective-C data source. Runtime protocol membership is checked before use. The Objective-C public implementation is also supported when its class/ABI match. If neither bridge is available, a limited fallback reads evidenced `DOCThumbnailFittingImageView.node/url` getters on genuinely visible selected cells, requiring exactly one URL per cell. Missing mappings reject the whole action before file operations. No forced dequeue or displayed-text path is used. Actual device/provider integration remains unverified; the runtime gate fails closed.

The snapshot does not establish a callable Files private transfer task or its callback contract. This release instead uses public Foundation NSFileCoordinator and NSFileManager copy/move, holds available security scopes, sends move notifications, refuses replacement and never implements move as copy-then-delete. Only real file URLs currently accessible to Files are supported. Provider-only locations without a materialized URL and unready iCloud placeholders return explicit errors. No claim of all-provider compatibility or completed cloud synchronization.

Each action snapshots the source selection and the other pane's current folder at invocation. Work is asynchronous, serialized per container, stops on the first failure and reports the number actually completed. A successful move is based on the native move return value, not on UI optimism. Prior successful items are not rolled back; file-provider mutations are not a batch transaction. The plugin does not test against or delete user files during development.

## Home

Each pane has Set current folder as home / Clear home in its bottom menu. Only valid directory URLs with a bookmark that round-trips are saved, in the independent `dev.filesdualpane.home` domain (`left` / `right`). iOS-compatible minimal bookmarks retain the URL's available sandbox authorization; no unsupported macOS security-scope bookmark option or private location serialization is used.

On entry, resolve without UI, validate directory/readiness, then use public `revealDocumentAtURL:importIfNeeded:NO:completion:`. Success is reported only if the native current directory equals the requested home. If the system merely selects the folder rather than entering it, the status explicitly says to open the located folder; this remains a known platform-dependent limitation, not a falsely confirmed restore. Invalid/revoked/deleted/unready homes keep native browsing available and report the error. No random container path is persisted as a home substitute. Clearing one pane does not affect the other.

The uninstall script removes only this plugin's exact preferences filename from mobile preferences / app preference directories, never Files preferences or documents. Existing cfprefsd caches may require normal app/process restart to disappear fully.

## Verification

CI runs source safety checks, the production Swift bridge against a host model of UIKit's public generic API (different generic specializations, unsupported source and offscreen index), production Foundation transfer/bookmark and selection-mapping functions against generated temporary fixtures, existing production transient-state and preview tests, and the real mixed Swift/Objective-C iOS build/package/signature checks. Fixtures cover offscreen selection, visible-node fallback and all-or-none rejection, missing-node URL rejection, source/target mapping, copy/move, conflict with source retained, missing sources, self/descendant rejection, independent home bookmarks, corrupt/deleted bookmarks and bounded dynamic-font row policy. These are not on-device UIKit rendering or third-party-provider integration tests.

No new device report capture is requested or compiled into this release.
