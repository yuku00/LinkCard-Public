# Files DualPane 0.4.0

RootHide tweak for **Files on iOS 16.6, build 20G75 only**. Package identifier remains `dev.filesdualpane.nativeprobe` so this replaces the earlier experimental package rather than installing a second tweak.

## Use

Open Files and use the **双窗格** button in the native navigation bar. The fullscreen container hosts **two newly constructed `DOCSplitBrowserViewController` instances**, not two document pickers and not reparented original controllers. Each has its own copied configuration, Full browser, hierarchy, document manager, data source, action manager and internal navigation controller, checked against the original and the other pane before presentation. Native source discovery uses the existing shared source observer.

- **并排** shows both real native browsers.
- **左栏 / 右栏** expands one while keeping the other browser and its current navigation alive.
- Narrow windows initially show the left pane; windows at least 700 points wide initially show both. Users can select either layout at any width. Per-pane public size-class overrides let UIKit adapt native sidebar navigation; no private sidebar enum is guessed.
- **关闭** dismisses to the original Files page. The original root and tabs are never replaced. Owned children are detached and references cleared; the shared source observer is never stopped and foreign subscription tokens are never removed.

## Scope

This is a native **dual-browser release**, not a complete MT file manager. It does not implement cross-pane copy/move, conflict handling, file deletion, file opening or preview forwarding. Native document-open delegate callbacks show a scope explanation; the existing preview/context-menu guards apply only inside our panes. Document creation and drag/drop are disabled for copied configurations. Other native action routes are **not a write sandbox**: use the original Files UI for file operations.

Two simultaneously displayed instances, layout adaptation, and their complete device-level navigation/teardown remain new code requiring ordinary use feedback; successful compilation or host tests do not certify them on a device. No further collection round is requested.

## Privacy, state and removal

The production target builds **only `Entry.m` and `DualPane.m`**. It does not start the old lifecycle recorder, expose a report/export overlay, log to disk, network, write global Files preferences or implement any file operation. Existing experimental sources are historical and not linked.

Copied configurations receive unique `dev.filesdualpane.session.*` identifiers. An ABI-checked, namespace-scoped `DOCUserInterfaceStateStore` adapter keeps their interface states in memory and bypasses its two persistent-write entrypoints; original configurations pass through unchanged. Only copied configurations disable save/restore of the last visited location. Close, failed construction and pane destruction discard owned in-memory states. No global defaults domain or native history is deleted. Normal Files/provider history and network behavior remains native and is not suppressed globally.

These state-store APIs have header evidence and production-wrapper host tests, not a new device certification. If their runtime ABI differs, entry fails before constructing panes. The old experimental UUID state may already have been persisted by Files; this release does not guess its defaults keys or purge the user's domain. Absolute removal of any historic native state cannot be promised without evidence of the exact owned keys.

Uninstall the package normally and fully terminate/reopen Files to unload the injected code and hooks. There is no plugin settings file, daemon, cache or log to clean. No removal script touches Files data.

## Build

Dedicated workflow: `.github/workflows/files-native-probe-roothide.yml`. It runs source checks, compiles and executes tests using the actual production state-wrapper code, builds with RootHide Theos for arm64 and arm64e, verifies package metadata and both Mach-O slices, and publishes a SHA-256 manifest. Tests do not replace device UI verification.
