# Files DualPane 0.7.1

## UI changes

- Always two equal-width native panes. Removed the parallel/left/right segment and the plugin bottom toolbar.
- Header: left ellipsis menu operates on pane 0, centered Close button, right ellipsis menu operates on pane 1. Native per-pane navigation/search/context menus remain untouched.
- Status starts collapsed; operations expose one truncated line under the header. Tap it to read the complete message/error.
- Known `DOCThumbnailFittingImageView` thumbnails use a 20-point slot, not merely smaller image bounds. The public horizontal `UIStackView` arranged thumbnail container's width is replaced with 20 points and its following spacing is 6 points. `UIListContentConfiguration` also gets a 20-point reserved image size. Native stack label frames remain constraint-driven.
- Filter only the public `UICellAccessoryMultiselect` accessory, retaining disclosure/progress/other accessories. No image/circle/button heuristic and no change to collection selection capabilities or selected index paths.
- Selection background follows `cell.isSelected`, updates through native `setSelected:` and layout, and preserves the VoiceOver Selected trait. Tint alpha is 0.16 light / 0.28 dark.
- Restore original thumbnail constraints, spacing, geometry, fonts and accessories before reuse or leaving the plugin list scope. Original native layout executes once after preview restoration.

## Preserved behavior

Cross-pane selection mapping, coordinated copy/move, conflict behavior, home bookmarks, cold-start parallel lists, isolated native factories and uninstall cleanup are unchanged. No new diagnostic collection was added.

## Verification

`tests/check_071.py` checks header bindings/center close, absent mode/bottom bar, status/full error access, thumbnail-slot compaction, exact multiselect filtering and restore wiring. `tests/ui_host.py` executes the production selection-visual functions using Foundation view doubles: selected/deselected state, light/dark tint, accessibility bits, accessory preservation, restoration and reuse. Existing production file-core, generic Swift diffable bridge, preview and transient-state fixtures remain in CI.

This is not a UIKit renderer or real-device Files test. The thumbnail slot branch depends on the native horizontal arranged-subview structure; unknown nonmatching native hierarchy retains its layout rather than using Swift offsets/KVC or hiding arbitrary controls. Verify actual thumbnail alignment, provider-specific rows, context previews, Dynamic Type, and select-all on the target iOS 16.6 device. The supplied screenshot proves one local move succeeded 1/1, not all providers or cloud synchronization.
