// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit
import CoreImage.CIFilterBuiltins
import ImageIO

struct RenderedCard {
    let image: UIImage
    let frame: Data
}

enum CardRenderer {
    static func canvas(_ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).image { c in
            UIColor.white.setFill()
            c.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            draw(c.cgContext)
        }
    }
    static func photo(data: Data) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else { throw CardError.message("无法解码照片，请选择静态图片") }
        return UIImage(cgImage: cg)
    }
    static func compose(_ image: UIImage, fill: Bool, turns: Int) -> UIImage {
        canvas { ctx in
            ctx.translateBy(x: 100, y: 100)
            ctx.rotate(by: CGFloat(turns % 4) * .pi / 2)
            let scale = fill ? max(200/image.size.width, 200/image.size.height)
                             : min(200/image.size.width, 200/image.size.height)
            let size = CGSize(width: image.size.width*scale, height: image.size.height*scale)
            image.draw(in: CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height))
        }
    }
    static func note(_ text: String, size: Double) -> UIImage {
        canvas { _ in
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            (text as NSString).draw(in: CGRect(x: 12, y: 12, width: 176, height: 176), withAttributes: [
                .font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black, .paragraphStyle: style
            ])
        }
    }
    static func qr(_ text: String) throws -> UIImage {
        guard !text.isEmpty, text.utf8.count <= 160 else { throw CardError.message("二维码请输入 1–160 个 UTF-8 字节；建议短链接") }
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let ci = f.outputImage, let cg = CIContext().createCGImage(ci, from: ci.extent) else {
            throw CardError.message("二维码生成失败")
        }
        // Integer module scale, at least four white modules on each side; no dithering.
        let moduleCount = cg.width
        let scale = 200 / (moduleCount + 8)
        guard scale >= 2 else { throw CardError.message("二维码过密，请缩短内容") }
        let side = CGFloat(moduleCount*scale)
        return canvas { ctx in
            ctx.interpolationQuality = .none
            UIImage(cgImage: cg).draw(in: CGRect(x: (200-side)/2, y: (200-side)/2, width: side, height: side))
        }
    }
    /// Static local-time calendar artwork; never a device clock or a background timer.
    static func dateCard(_ date: Date, style: Int) -> UIImage {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let year = parts.year ?? 2000, month = parts.month ?? 1, day = parts.day ?? 1
        let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
        return canvas { ctx in
            func label(_ text: String, _ rect: CGRect, _ size: CGFloat, bold: Bool = false, white: Bool = false) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                (text as NSString).draw(in: rect, withAttributes: [
                    .font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size),
                    .foregroundColor: white ? UIColor.white : UIColor.black,
                    .paragraphStyle: paragraph
                ])
            }
            if style == 2 {
                label("\(year) 年 \(month) 月", CGRect(x: 8, y: 12, width: 184, height: 28), 20, bold: true)
                for column in 0..<7 {
                    label(weekdays[(column+1)%7], CGRect(x: 9+column*26, y: 48, width: 26, height: 20), 12)
                }
                guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                      let range = calendar.range(of: .day, in: .month, for: first) else { return }
                let offset = (calendar.component(.weekday, from: first)+5)%7
                for number in range {
                    let index = offset+number-1
                    let rect = CGRect(x: 9+(index%7)*26, y: 74+(index/7)*18, width: 26, height: 18)
                    if number == day { UIColor.black.setFill(); ctx.fill(rect.insetBy(dx: 2, dy: 0)) }
                    label("\(number)", rect, 13, bold: number == day, white: number == day)
                }
            } else {
                label("\(year) 年 · \(month) 月", CGRect(x: 10, y: 20, width: 180, height: 28), 18)
                label(String(format: "%02d", day), CGRect(x: 8, y: 49, width: 184, height: 106), 88, bold: true)
                let footer = style == 1 ? "星期" + weekdays[(parts.weekday ?? 1)-1] : "\(year).\(String(format: "%02d", month)).\(String(format: "%02d", day))"
                label(footer, CGRect(x: 10, y: 161, width: 180, height: 28), 18, bold: true)
            }
        }
    }
    static func checklist(_ text: String) -> UIImage {
        canvas { ctx in
            ("待办 · 慢慢来" as NSString).draw(at: CGPoint(x: 12, y: 12), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.black
            ])
            let items = text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(5)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            UIColor.black.setStroke()
            ctx.setLineWidth(1.5)
            for (index, item) in items.enumerated() {
                let y = 53 + index*28
                ctx.stroke(CGRect(x: 13, y: y+3, width: 13, height: 13))
                (item as NSString).draw(in: CGRect(x: 35, y: y, width: 153, height: 24), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.black, .paragraphStyle: paragraph
                ])
            }
        }
    }
    static func test(_ kind: Int) -> UIImage {
        canvas { ctx in
            UIColor.black.setFill()
            if kind == 0 { ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200)) }
            if kind == 2 {
                for y in 0..<10 { for x in 0..<10 where (x+y)%2 == 0 {
                    ctx.fill(CGRect(x: x*20, y: y*20, width: 20, height: 20))
                }}
            }
            if kind == 3 {
                ("↑ 顶部 TOP" as NSString).draw(at: CGPoint(x: 20, y: 12), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.black])
                ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
                ctx.fill(CGRect(x: 20, y: 60, width: 30, height: 120))
                ("下 ↓" as NSString).draw(at: CGPoint(x: 110, y: 163), withAttributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.black])
            }
        }
    }
    static func render(_ source: UIImage, threshold: Double, dither: Bool) throws -> RenderedCard {
        guard let cg = source.cgImage, cg.width == 200, cg.height == 200 else { throw CardError.message("无有效画布") }
        var gray = [UInt8](repeating: 255, count: 40_000)
        let success = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: 200, height: 200, bitsPerComponent: 8,
                                      bytesPerRow: 200, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 200, height: 200))
            return true
        }
        guard success else { throw CardError.message("灰度画布创建失败") }
        var work = gray.map(Double.init)
        for y in 0..<200 { for x in 0..<200 {
            let i = y*200+x
            let old = work[i]
            let value: Double = old > threshold ? 255 : 0
            gray[i] = UInt8(value)
            if dither {
                let e = old-value
                if x < 199 { work[i+1] += e*7/16 }
                if y < 199 {
                    if x > 0 { work[i+199] += e*3/16 }
                    work[i+200] += e*5/16
                    if x < 199 { work[i+201] += e/16 }
                }
            }
        }}
        guard let provider = CGDataProvider(data: Data(gray) as CFData),
              let result = CGImage(width: 200, height: 200, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 200,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw CardError.message("预览生成失败")
        }
        return RenderedCard(image: UIImage(cgImage: result), frame: try FrameCodec.encode(gray))
    }
}
