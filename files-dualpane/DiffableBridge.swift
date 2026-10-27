import UIKit

// Conformance to a local Swift protocol preserves the real generic specialization.
// No reflection, private storage or conversion to the unrelated ObjC data source.
private protocol FPRealDiffableSource {
    func fpNode(at indexPath: IndexPath) -> AnyObject?
}

extension UICollectionViewDiffableDataSource: FPRealDiffableSource {
    fileprivate func fpNode(at indexPath: IndexPath) -> AnyObject? {
        guard let item = itemIdentifier(for: indexPath) else { return nil }
        return item as AnyObject
    }
}

@objc(FPDiffableBridge)
final class FPDiffableBridge: NSObject {
    @objc(supportsDataSource:)
    static func supportsDataSource(_ dataSource: AnyObject) -> Bool {
        return dataSource is FPRealDiffableSource
    }

    @objc(nodeFrom:indexPath:)
    static func node(from dataSource: AnyObject, indexPath: NSIndexPath) -> AnyObject? {
        guard Thread.isMainThread, let source = dataSource as? FPRealDiffableSource else { return nil }
        return source.fpNode(at: indexPath as IndexPath)
    }
}
