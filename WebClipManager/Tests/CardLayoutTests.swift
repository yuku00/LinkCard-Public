import XCTest
import UIKit
@testable import WebClipManager

@MainActor final class CardLayoutTests: XCTestCase {
    func testHugeImageDoesNotGrowActualUIKitRow() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2048, height: 2048))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2048, height: 2048))
        }
        let thumbnail = try XCTUnwrap(GlassCell.thumbnail(try XCTUnwrap(image.pngData())))
        XCTAssertLessThanOrEqual(try XCTUnwrap(thumbnail.cgImage).width, 96)
        let cell = GlassCell(style: .default, reuseIdentifier: nil)
        cell.configure(title: "Synthetic bookmark", subtitle: "https://example.invalid", icon: image, selected: true)
        let width: CGFloat = 358
        let height = cell.contentView.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        XCTAssertLessThan(height, 180)
        XCTAssertGreaterThanOrEqual(height, 88)
        cell.frame = CGRect(x: 0, y: 0, width: width, height: height)
        cell.setNeedsLayout(); cell.layoutIfNeeded()
        XCTAssertEqual(cell.iconContainer.bounds.width, 44, accuracy: 0.5)
        XCTAssertEqual(cell.iconContainer.bounds.height, 44, accuracy: 0.5)
        XCTAssertEqual(cell.iconView.bounds.width, 32, accuracy: 0.5)
        XCTAssertEqual(cell.iconView.bounds.height, 32, accuracy: 0.5)
        let screenshot = UIGraphicsImageRenderer(bounds: cell.bounds).image { ctx in cell.layer.render(in: ctx.cgContext) }
        let attachment = XCTAttachment(image: screenshot); attachment.name = "synthetic-large-icon-card"; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
