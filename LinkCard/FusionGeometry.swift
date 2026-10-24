// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Presentation-only state. Card IDs, storage, NFC and BLE never enter this model.
final class FusionState: ObservableObject {
    var rootBodyCount = 0
    weak var drawerOwner: DrawerRenderOwner?
    // Legacy geometry probes remain isolated; production frames live in drawerOwner.
    @Published var drawer: CGFloat = 0 { didSet { presentedDrawer = drawer } }
    @Published var bend: CGFloat = 0
    @Published var touchY: CGFloat = 280
    @Published var search = ""
    @Published var profile = false
    var presentedDrawer: CGFloat = 0
    var dragOrigin: CGFloat?
    static func drawerWidth(_ width: CGFloat) -> CGFloat { min(280, max(0, width * 0.65)) }
    static func clamp(_ value: CGFloat, width: CGFloat) -> CGFloat { min(width, max(0, value)) }
    static func destination(position: CGFloat, predicted: CGFloat, width: CGFloat) -> CGFloat {
        position + predicted > width * 0.47 ? width : 0
    }
    func drag(translation: CGFloat, predicted: CGFloat, width: CGFloat, y: CGFloat) {
        if dragOrigin == nil { dragOrigin = presentedDrawer }
        let raw = (dragOrigin ?? 0) + translation
        drawer = Self.clamp(raw, width: width)
        presentedDrawer = drawer
        // Position/stretch remains visible at slow speed; velocity contributes but
        // never owns the deformation. Smooth signed saturation allows reversal.
        let stretch = translation * 0.28 + (predicted - translation) * 0.08 + (raw - drawer) * 0.55
        bend = 36 * stretch / (36 + abs(stretch))
        touchY = y
    }
    func finish(predictedDelta: CGFloat, width: CGFloat) {
        drawer = Self.destination(position: drawer, predicted: predictedDelta, width: width)
        bend = 0; dragOrigin = nil
    }
}

/// Complete vertical edge at rest; only a local cubic segment deforms during drag.
struct FusionDrawerShape: Shape {
    var bend: CGFloat
    var touchY: CGFloat
    var trailingSpace: CGFloat = 0
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bend, touchY) }
        set { bend = newValue.first; touchY = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let reach = min(190, rect.height * 0.28)
        let y = min(max(reach + 36, touchY), max(reach + 36, rect.height - reach - 36))
        let x = rect.maxX - trailingSpace
        let shoulder = min(36, rect.height * 0.08)
        let curve = bend - 14 // A broad, soft inward edge remains visible at rest.
        return Path { p in
            p.move(to: .zero); p.addLine(to: CGPoint(x: x - shoulder, y: 0))
            p.addQuadCurve(to: CGPoint(x: x, y: shoulder * 2), control: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: y - reach))
            p.addCurve(to: CGPoint(x: x + curve, y: y), control1: CGPoint(x: x, y: y - reach * 0.45), control2: CGPoint(x: x + curve, y: y - reach * 0.45))
            p.addCurve(to: CGPoint(x: x, y: y + reach), control1: CGPoint(x: x + curve, y: y + reach * 0.45), control2: CGPoint(x: x, y: y + reach * 0.45))
            p.addLine(to: CGPoint(x: x, y: rect.maxY - shoulder * 2))
            p.addQuadCurve(to: CGPoint(x: x - shoulder, y: rect.maxY), control: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: 0, y: rect.maxY)); p.closeSubpath()
        }
    }
}

/// Reports the interpolated position, not merely the spring destination. A new drag
/// grabs this displayed position and may reverse before the previous spring ends.
struct FusionPresentation: AnimatableModifier {
    var x: CGFloat
    let width: CGFloat
    let state: FusionState
    var animatableData: CGFloat {
        get { x }
        set {
            x = newValue
            // Non-published presentation sample: no body side effect, task queue,
            // Preference emission or objectWillChange. Used only at gesture begin.
            state.presentedDrawer = newValue
        }
    }
    func body(content: Content) -> some View { content.offset(x: x - width) }
}

struct FusionNotch: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: rect, cornerRadius: 30)
        p.addEllipse(in: CGRect(x: rect.midX - 37, y: -37, width: 74, height: 74))
        return p
    }
}

struct FusionClock: View {
    var vertical = false
    var compact = false
    var body: some View {
        // Displayed precision is one minute. Align refreshes to minute boundaries;
        // TimelineView invalidates only this local clock, never the shell state.
        TimelineView(.everyMinute) { context in
            if vertical {
                VStack(spacing: 14) {
                    Text(context.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)))
                    Rectangle().frame(width: 20, height: 1)
                    Text(context.date, format: .dateTime.minute(.twoDigits))
                    Text(context.date, format: .dateTime.month(.twoDigits).day(.twoDigits)).font(.caption)
                }.font(.system(.title, design: .rounded).weight(.light)).monospacedDigit()
            } else {
                VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                    Text(context.date, style: .time).font(.system(size: compact ? 32 : 42, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    // Bounded live-clock typography; the full date remains available to VoiceOver.
                    Text(context.date, format: .dateTime.month().day().weekday())
                        .font(.system(size: compact ? 14 : 17, weight: .medium)).lineLimit(1).minimumScaleFactor(0.65)
                }
            }
        }.accessibilityLabel("本地时间")
    }
}
