// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit

/// One presentation value drives every workbench frame. No delayed child springs.
final class FusionProgress: NSObject, ObservableObject {
    @Published private(set) var value: CGFloat = 1
    private var target: CGFloat = 1
    private var velocity: CGFloat = 0
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private final class Tick: NSObject {
        weak var owner: FusionProgress?
        @objc func step(_ link: CADisplayLink) { owner?.step(link) }
    }
    private let tick = Tick()
    private var active = UIApplication.shared.applicationState == .active
    private(set) var tickCount = 0
    var isRunning: Bool { link != nil }
    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(suspend), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(suspend), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    @objc private func suspend() { setSceneActive(false) }
    @objc private func resume() { setSceneActive(true) }
    func setSceneActive(_ active: Bool) {
        self.active = active
        stop(); velocity = 0
        // Settle without background rendering; foreground resumes at final intent.
        if value != target { value = target }
    }
    func move(to target: CGFloat, immediately: Bool = false) {
        self.target = min(2, max(0, target))
        if immediately || !active { stop(); value = self.target; velocity = 0; return }
        if abs(self.target - value) < 0.001 && abs(velocity) < 0.01 { stop(); return }
        guard link == nil else { return }
        tick.owner = self; last = 0
        let display = CADisplayLink(target: tick, selector: #selector(Tick.step(_:)))
        display.add(to: .main, forMode: .common); link = display
    }
    func track(_ value: CGFloat) { stop(); self.value = min(2, max(0, value)); velocity = 0 }
    private func step(_ display: CADisplayLink) {
        guard active else { stop(); return }
        tickCount += 1
        let dt = CGFloat(min(1.0 / 30, last == 0 ? 1.0 / 60 : display.timestamp - last))
        last = display.timestamp
        // Critically damped: no geometry overshoot into neighbouring text.
        velocity += (260 * (target - value) - 32 * velocity) * dt
        value = min(2, max(0, value + velocity * dt))
        if abs(target - value) < 0.001 && abs(velocity) < 0.01 { value = target; stop() }
    }
    func stop() { link?.invalidate(); link = nil; last = 0 }
    deinit { link?.invalidate(); NotificationCenter.default.removeObserver(self) }
}

/// A handle drag samples a stable ancestor coordinate space and freezes its
/// detent/travel until release. Content scrolling never creates this sample.
struct FusionWorkbenchDrag: Equatable {
    let origin: CGFloat
    let travel: CGFloat
    let size: CGSize
    let keyboard: Bool
    let accessibility: Bool
    let vertical: Bool
    private(set) var progress: CGFloat
    init(origin: CGFloat, travel: CGFloat, size: CGSize, keyboard: Bool,
         accessibility: Bool, translation: CGSize) {
        self.origin = origin; self.travel = max(1, travel); self.size = size
        self.keyboard = keyboard; self.accessibility = accessibility
        vertical = abs(translation.height) > abs(translation.width)
        progress = origin
        self = tracking(translation)
    }
    func tracking(_ translation: CGSize) -> Self {
        var next = self
        if vertical { next.progress = min(2, max(1, origin - translation.height / travel)) }
        return next
    }
    func expanded(predictedTranslation: CGFloat) -> Bool {
        origin - predictedTranslation / travel > 1.5
    }
    func matches(size: CGSize, keyboard: Bool, accessibility: Bool) -> Bool {
        self.size == size && self.keyboard == keyboard && self.accessibility == accessibility
    }
}

/// Non-observed release metadata: GestureState may reset before onEnded runs.
/// This is assigned only at begin/end, never a second per-frame view publisher.
final class FusionWorkbenchDragSession {
    var start: FusionWorkbenchDrag?
}

/// Shared production geometry for intermediate progress and test assertions.
struct FusionWorkbenchGeometry {
    let panel: CGRect
    let avatar: CGRect
    let handle: CGRect
    let header: CGRect
    let content: CGRect
    let tabs: CGRect
    let travel: CGFloat
    init(size: CGSize, progress: CGFloat, keyboard: Bool = false, accessibility: Bool = false) {
        let p = min(2, max(1, progress))
        // Geometry is in the safe interactive rectangle. Background alone extends
        // beneath the home indicator, so there is neither a root bar nor a spacer.
        let top: CGFloat = keyboard ? 0 : (size.height < 600 ? 64 : 92) + 44
        let expanded = max(0, size.height - top)
        let compact = min(accessibility ? 360 : 300, expanded * 0.72)
        travel = max(1, expanded - compact)
        let height = compact + (expanded - compact) * (p - 1)
        let y = size.height - height
        panel = CGRect(x: 0, y: y, width: max(0, size.width), height: height)
        avatar = CGRect(x: size.width / 2 - 28, y: y - 28, width: 56, height: 56)
        handle = CGRect(x: max(0, size.width - 100), y: y, width: 88, height: min(44, height))
        header = CGRect(x: 0, y: handle.maxY, width: panel.width, height: min(44 * (p - 1), max(0, height - 44)))
        let tabHeight = min(accessibility ? 116 : 72, max(0, height - 88))
        tabs = CGRect(x: 0, y: panel.maxY - tabHeight, width: panel.width, height: tabHeight)
        content = CGRect(x: 0, y: header.maxY, width: panel.width, height: max(0, tabs.minY - header.maxY))
    }
}

/// Native control used in production: tests must hit the actual UIWindow and send
/// UIControl touch-up to the hit UIButton, not call a view's action closure.
struct FusionButton: UIViewRepresentable {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let symbol: String
    let id: String
    var selected = false
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
        // Scale once here, not again through UIButton's configuration/UILabel.
        // These compact navigation controls keep bounded symbols; page text still
        // uses the user's unrestricted Dynamic Type setting.
        let pointSize: CGFloat = typeSize.isAccessibilitySize ? 20 : (typeSize >= .xxxLarge ? 19 : 17)
        configure(button, coordinator: context.coordinator, pointSize: pointSize)
    }
    // Shared production path, exercised directly with real UIKit in regression tests.
    func configure(_ button: UIButton, coordinator: Coordinator, pointSize: CGFloat) {
        coordinator.action = action
        let key = RenderKey(title: title, symbol: symbol, id: id, selected: selected, pointSize: pointSize)
        guard coordinator.renderKey != key else { return }
        coordinator.renderKey = key
        coordinator.configurationCommitCount += 1
        Coordinator.totalConfigurationCommits += 1
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold, scale: .medium)
        var config = UIButton.Configuration.plain()
        config.title = ["workbench.handle", "fusion.menu", "fusion.close"].contains(id) ? nil : title
        config.image = symbol.isEmpty ? nil : UIImage(systemName: symbol, withConfiguration: symbolConfiguration)
        config.preferredSymbolConfigurationForImage = symbolConfiguration
        config.imagePlacement = .leading
        config.imagePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
        config.titleLineBreakMode = .byClipping
        config.baseForegroundColor = UIColor(MistStyle.ink)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var next = attributes; next.font = UIFont.systemFont(ofSize: pointSize, weight: .semibold); return next
        }
        button.configuration = config
        button.titleLabel?.adjustsFontForContentSizeCategory = false
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.8
        button.titleLabel?.baselineAdjustment = .alignCenters
        button.imageView?.adjustsImageSizeForAccessibilityContentSizeCategory = false
        button.accessibilityIdentifier = id
        button.accessibilityLabel = title; button.isSelected = false // Selection is drawn by the shared rounded SwiftUI surface, not UIKit's rectangular tint.
        button.accessibilityTraits = selected ? [.button, .selected] : .button
    }
    struct RenderKey: Equatable {
        let title: String
        let symbol: String
        let id: String
        let selected: Bool
        let pointSize: CGFloat
    }
    final class Coordinator: NSObject {
        static var totalConfigurationCommits = 0
        var renderKey: RenderKey?
        var configurationCommitCount = 0
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}
