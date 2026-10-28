# Files DualPane 0.7.7

A focused document-thumbnail fix over 0.7.6. The working folder constant-size planner, independent accessory filtering, selection handling, native actions and Files-only scope remain in place.

## Fixed branch

The previous planner accepted only constant dimensions and unit equality links. A normal `image.width = ratio * image.height` constraint with a non-unit multiplier rejected the entire native style plan. The thumbnail finder also excluded the evidenced `DOCFittingImageView` base class (the documented chain is `DOCThumbnailFittingImageView -> DOCBorderedFittingImageView -> DOCFittingImageView -> UIImageView`).

The new branch is limited to a unique known DOC fitting image obtained under the ABI-checked accessibility thumbnail getter, in the existing horizontal arranged slot adjacent to the accessibility title slot. It reads active constraints, not private storage. It preserves the native self-aspect constraint and fits the image inside 20 x 20 points (e.g. a 2:3 document becomes 13.33 x 20), rather than forcing a square preview. Standalone fixed widths/heights, direct image slots, and exact width/height equality links to the known slot are handled. A width-coupled slot follows the fitted image width; otherwise its width becomes 20. Known row edges retain 10-point left/right insets and the thumbnail gap is 6.

Capabilities are separated: a verified standalone image can shrink even if the outer slot/row edges cannot; safe label fonts can apply even when the dimension graph is unsupported; oversized text does not block verified image sizing. A slot is never shrunk around an unshrinkable image. Unknown/foreign geometry is left alone. Existing native cell height is not changed and must be at least 44 points. Selection, image contents and file actions are not changed.

There is no cell transform, generic UIImageView/UILabel walk, Swift offset, controller layout scan, per-layout styling, home/Downloads restoration, new collection or Mail change. Existing event-driven state/reentry protection and restore logic remain. Native aspect replacement invalidates a saved sizing plan through the retained constraint's active state.

## Tests and evidence boundary

The new Foundation/CoreGraphics fixtures execute the production Objective-C functions and evaluate the resulting dimension equations. Cases include portrait document, landscape preview, blank fitting icon, width-coupled slot, direct image slot, height-coupled slot, independent image/fonts fallback, original selected/unselected state, 44-point gate, replaced native aspect, repeated events with zero writes, restoration, and the existing folder fixture.

Before modifying the production planner, the new portrait fixture failed at `AssertDocument` against unchanged 0.7.6 in run 40648890307. This is a real old-code failure, not a replacement planner or a stubbed success result. The final CI also checks deliberate margin, native-size and document-square mutations, other existing production host fixtures, RootHide package metadata, arm64 + arm64e slices and embedded signatures.

These tests inspect plans and state on host doubles; they are not the UIKit layout solver or a real-device UI result. The existing metadata establishes the class/ratio API, not that every provider uses this exact slot graph. Foreign anchors, multiple known thumbnails, nonzero dimension offsets, unsupported ratio equations and non-horizontal/nonadjacent layouts are not forced. Actual Files document rows still require installation testing; no new capture is requested.
