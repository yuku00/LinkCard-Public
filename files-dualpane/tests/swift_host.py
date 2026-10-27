from pathlib import Path
import sys
r=Path(__file__).resolve().parents[1]
source=(r/'DiffableBridge.swift').read_text().replace('import UIKit','import Foundation',1)
model='''
// Host seam: UIKit is unavailable on macOS; model only its public generic API.
class UICollectionViewDiffableDataSource<Section: Hashable, Item: Hashable>: NSObject {
    var items: [IndexPath: Item] = [:]
    func itemIdentifier(for indexPath: IndexPath) -> Item? { items[indexPath] }
}
'''
test='''
struct NativeSection: Hashable { let value: Int }
final class NativeItem: NSObject {}
let left = UICollectionViewDiffableDataSource<NativeSection, NativeItem>()
let right = UICollectionViewDiffableDataSource<String, NativeItem>()
let item = NativeItem(), other = NativeItem()
let path = IndexPath(index: 999)
left.items[path] = item
right.items[path] = other
assert(FPDiffableBridge.supportsDataSource(left))
assert(FPDiffableBridge.supportsDataSource(right))
assert(!FPDiffableBridge.supportsDataSource(NSObject()))
assert(FPDiffableBridge.node(from: left, indexPath: path as NSIndexPath) === item)
assert(FPDiffableBridge.node(from: right, indexPath: path as NSIndexPath) === other)
assert(FPDiffableBridge.node(from: left, indexPath: IndexPath(index: 1000) as NSIndexPath) == nil)
assert(FPDiffableBridge.node(from: NSObject(), indexPath: path as NSIndexPath) == nil)
print("PASS production Swift protocol bridge with public-API host model: different generic specializations, independent sources, offscreen index, missing item and unsupported source")
'''
Path(sys.argv[1]).write_text(source+model+test)
