// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit

/// One rendering owner; no ObservableObject writes in the display-link path.
final class DrawerRenderOwner: UIViewController, UIGestureRecognizerDelegate {
    enum Phase: String { case closed, manual, position, shape, open }
    private(set) var phase: Phase = .closed
    private(set) var q: CGFloat = 0
    private(set) var touchY: CGFloat = 0
    private(set) var generation = 0
    private(set) var frameCount = 0
    private(set) var menuUpdateCount = 0
    private(set) var targetOpen = false
    // Opt-in test diagnostics: no per-frame dispatch or user-content logging.
    private var auditedOpen = false
    var auditBindingMatches = false
    var auditBusy = false
    private var clickAuditEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-DrawerClickAudit") }
    private(set) var sceneActive = true
    private(set) var width: CGFloat = 0
    private(set) var outline: [CGPoint] = []
    var reduceMotion = false
    let surface = UIView()
    let blur = MistEffectView()
    let maskLayer = CAShapeLayer()
    private let effectMask = UIView()
    private let contentClip = UIView()
    private let contentMask = CAShapeLayer()
    let menu = UIHostingController(rootView: AnyView(EmptyView()))
    lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private var link: CADisplayLink?
    var isRunning: Bool { link != nil }
    private var observers: [NSObjectProtocol] = []
    private var startTime: CFTimeInterval = 0
    private var duration: CFTimeInterval = 0
    private var qStart: CGFloat = 0
    private var startOutline: [CGPoint] = []
    private var openingDrag = true
    private var consumed = false
    private var fingerCount = 0
    private var lastTranslation: CGFloat = 0
    private var pickupOutline: [CGPoint] = []
    private var pickupQ: CGFloat = 0
    private var oldSize = CGSize.zero
    // Provisional normalization uses the analysis' W=864 mathematical example,
    // NOT a measured Android screenshot/density. Device visual calibration is pending.
    private var smoothReturn = false
    private var preservePickup = false
    private var cAmplitude: CGFloat { width * 150 / 864 }
    private var eAmplitude: CGFloat { width * 100 / 864 }
    private final class Tick: NSObject {
        weak var owner: DrawerRenderOwner?
        let generation: Int
        init(_ owner: DrawerRenderOwner) { self.owner = owner; generation = owner.generation }
        @objc func fire(_ link: CADisplayLink) { owner?.advance(link.timestamp, generation: generation) }
    }
    override func loadView() {
        let root = DrawerHitView(); root.owner = self; view = root
        root.backgroundColor = .clear
        surface.backgroundColor = .clear; root.addSubview(surface)
        surface.addSubview(blur)
        let tint = UIView(); tint.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        tint.isUserInteractionEnabled = false; tint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blur.contentView.addSubview(tint)
        surface.addSubview(contentClip)
        addChild(menu); contentClip.addSubview(menu.view); menu.didMove(toParent: self)
        menu.view.backgroundColor = .clear; menu.view.isOpaque = false
        // Container insets are supplied by our menu frame, not by its moving host.
        // Keep keyboard avoidance; this public API is available on the target iOS 16.6.
        if #available(iOS 16.4, *) { menu.safeAreaRegions = .keyboard }
        // Never mask an effect's ancestor: UIKit explicitly disallows this.
        effectMask.layer.addSublayer(maskLayer)
        contentClip.layer.mask = contentMask
        pan.delegate = self; pan.maximumNumberOfTouches = 2
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false; pan.delaysTouchesEnded = false
        // The portal installs pan on the common content ancestor, not a tap shield.
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.setActive(false) })
        }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.setActive(true) })
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The background is window-sized; only interactive menu content is inset.
        let safe = view.window?.safeAreaInsets ?? view.safeAreaInsets
        let menuWidth = FusionState.drawerWidth(view.bounds.width)
        menu.view.frame = CGRect(x: safe.left, y: safe.top,
                                 width: max(0, menuWidth - safe.left),
                                 height: max(0, view.bounds.height - safe.top - safe.bottom))
        guard view.bounds.size != oldSize else { return }
        let wasOpen = targetOpen
        cancelClock(); oldSize = view.bounds.size
        width = FusionState.drawerWidth(view.bounds.width)
        surface.bounds = CGRect(x: 0, y: 0, width: width + cAmplitude, height: view.bounds.height)
        surface.center = CGPoint(x: surface.bounds.width / 2, y: view.bounds.height / 2)
        blur.frame = surface.bounds
        blur.contentView.subviews.first?.frame = blur.bounds
        contentClip.frame = surface.bounds
        effectMask.frame = blur.bounds
        maskLayer.frame = effectMask.bounds; contentMask.frame = contentClip.bounds
        q = wasOpen ? width : 0; phase = wasOpen ? .open : .closed
        touchY = min(max(touchY, 0), view.bounds.height)
        outline = quadratic(c: width, e: width); applyFrame()
    }
    func updateMenu(_ content: AnyView, strength: Double) {
        loadViewIfNeeded(); menuUpdateCount += 1
        menu.rootView = content; blur.setIntensity(strength)
    }
    func setActive(_ active: Bool) {
        sceneActive = active
        if !active {
            cancelClock(); consumed = false
            q = targetOpen ? width : 0; phase = targetOpen ? .open : .closed
            outline = quadratic(c: width, e: width); applyFrame()
            pan.isEnabled = false; pan.isEnabled = true
        }
    }
    func shutdown() { cancelClock(); observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll() }
    deinit { link?.invalidate(); observers.forEach(NotificationCenter.default.removeObserver) }
    func cancelClock() { generation += 1; link?.invalidate(); link = nil }
    private func runClock() {
        guard sceneActive, !reduceMotion else { finishImmediately(); return }
        let clock = CADisplayLink(target: Tick(self), selector: #selector(Tick.fire(_:)))
        link = clock; clock.add(to: .main, forMode: .common)
    }
    func request(open: Bool, velocity: CGFloat = 0, smooth: Bool = false) {
        guard sceneActive, width > 0 else { return }
        smoothReturn = smooth
        cancelClock(); targetOpen = open; qStart = q; startOutline = outline
        phase = .position; startTime = CACurrentMediaTime()
        let distance = abs((open ? width : 0) - q)
        duration = min(0.6, velocity == 0 ? 0.6 * Double(distance / width) : 4 * Double(distance / abs(velocity)))
        duration = smooth ? 0.5 : max(0.001, duration)
        runClock()
    }
    private func finishImmediately() {
        cancelClock(); q = targetOpen ? width : 0; phase = targetOpen ? .open : .closed
        outline = quadratic(c: width, e: width); applyFrame()
    }
    func advance(_ now: CFTimeInterval, generation token: Int) {
        guard token == generation, sceneActive else { return }
        let t = min(1, max(0, (now - startTime) / duration))
        if phase == .position {
            let s = CGFloat(smoothReturn ? 1 - pow(1 - t, 8) : 1 + pow(t - 1, 5))
            q = qStart + ((targetOpen ? width : 0) - qStart) * s
            var next = targetOpen ? openingOutline() : quadratic(c: (width + q) / 2, e: width)
            if smoothReturn {
                next = manualOutline()
                // Replace Android's draw-count-dependent 10 px expansion with elapsed time.
                let spread = CGFloat(t * 0.5 * 60) * width * 10 / 864
                for i in 0..<4 { next[i].y -= spread }
                for i in 5..<9 { next[i].y += spread }
            }
            outline = blend(startOutline, next, min(1, CGFloat(t) * 8))
            if t >= 1 {
                q = targetOpen ? width : 0
                if targetOpen {
                    phase = .shape; startTime = now; duration = 0.3
                    outline = quadratic(c: width + cAmplitude, e: width + eAmplitude)
                } else { phase = .closed; cancelClock() }
            }
        } else if phase == .shape {
            let u = CGFloat(t - 1); let a = u * u * (5 * u + 4) + 1
            outline = quadratic(c: width + cAmplitude * (1 - a), e: width + eAmplitude * (1 - a))
            if t >= 1 { phase = .open; cancelClock() }
        }
        applyFrame()
    }
    private func openingOutline() -> [CGPoint] {
        if q < width / 2 { return manualOutline() }
        let f = min(1, max(0, (q - width / 2) / (width / 2)))
        let fc = f <= 0.5 ? 2 * f * f : 1 + (sqrt(f) - 1) / (2 - sqrt(2))
        let fe = f <= 0.5 ? sqrt(f / 2) : (2 * f * f + 1) / 3
        let auto = quadratic(c: width / 2 + fc * (width / 2 + cAmplitude), e: 0.75 * width + fe * (width / 4 + eAmplitude))
        return blend(manualOutline(), auto, min(1, f / 0.16))
    }
    private func manualOutline() -> [CGPoint] {
        let h = max(1, view.bounds.height), y = touchY
        let r = abs((2 * y - h) / h), r1 = 1 + 3 * r, r2 = 1 + 5 * r
        let short = 0.7 * h / (r1 + 1) + 6 * q / (r2 + 1)
        let long = 0.7 * h / (1 + 1 / r1) + 6 * q / (1 + 1 / r2)
        let top = y - (y >= h / 2 ? long : short)
        let bottom = y + (y >= h / 2 ? short : long)
        let tc = y >= h / 2 ? -bottom / 4 + 5 * y / 4 : top / 4 + 3 * y / 4
        let bc = y >= h / 2 ? bottom / 4 + 3 * y / 4 : -top / 4 + 5 * y / 4
        let x = width - q
        return [CGPoint(x: x, y: top), CGPoint(x: x, y: top), CGPoint(x: x, y: tc), CGPoint(x: width, y: tc), CGPoint(x: width, y: y), CGPoint(x: width, y: bc), CGPoint(x: x, y: bc), CGPoint(x: x, y: bottom), CGPoint(x: x, y: bottom)]
    }
    private func quadratic(c: CGFloat, e: CGFloat) -> [CGPoint] {
        let h = view.bounds.height
        let a = CGPoint(x: e, y: 0), b = CGPoint(x: c, y: touchY), d = CGPoint(x: e, y: h)
        let ab = mix(a, b, 0.5), bd = mix(b, d, 0.5), mid = mix(ab, bd, 0.5)
        return [CGPoint(x: width - q, y: 0), a, mix(a, ab, 2/3), mix(mid, ab, 2/3), mid, mix(mid, bd, 2/3), mix(d, bd, 2/3), d, CGPoint(x: width - q, y: h)]
    }
    private func mix(_ a: CGPoint, _ b: CGPoint, _ f: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x-a.x)*f, y: a.y + (b.y-a.y)*f) }
    private func blend(_ a: [CGPoint], _ b: [CGPoint], _ f: CGFloat) -> [CGPoint] {
        guard a.count == b.count else { return b }
        return zip(a,b).map { mix($0.0, $0.1, f) }
    }
    private func applyFrame() {
        guard isViewLoaded, outline.count == 9 else { return }
        let p = CGMutablePath(); p.move(to: outline[0]); p.addLine(to: outline[1])
        p.addCurve(to: outline[4], control1: outline[2], control2: outline[3])
        p.addCurve(to: outline[7], control1: outline[5], control2: outline[6])
        p.addLine(to: outline[8]); p.closeSubpath()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        surface.transform = CGAffineTransform(translationX: q - width, y: 0)
        maskLayer.path = p; contentMask.path = p
        // UIVisualEffectView copies a UIView mask; reassign after path/size changes.
        blur.mask = nil; blur.mask = effectMask
        surface.isHidden = q <= 0
        surface.accessibilityElementsHidden = q <= 0
        // This UIKit child is outside its parent's SwiftUI accessibility graph.
        // While visible, exclude that graph's overlapping workbench siblings from
        // AX hit testing. UIKit already hits the menu correctly; do not reorder,
        // replace buttons, or broaden the physical mask to fix an AX boundary.
        view.accessibilityViewIsModal = q > 0
        CATransaction.commit(); frameCount += 1
        if phase != .open { auditedOpen = false }
        if clickAuditEnabled, phase == .open, !auditedOpen {
            auditedOpen = true
            let token = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.phase == .open, self.generation == token,
                      let window = self.view.window else { return }
                let p = self.view.convert(CGPoint(x: 121.65, y: 459), from: window)
                let local = self.menu.view.convert(p, from: self.view)
                let hostHit = self.menu.view.hitTest(local, with: nil)
                let ownerHit = self.view.hitTest(p, with: nil)
                let windowHit = window.hitTest(window.convert(p, from: self.view), with: nil)
                func kind(_ v: UIView?) -> String {
                    guard let v else { return "nil" }
                    return "\(type(of: v))#\(ObjectIdentifier(v))"
                }
                func chain(_ hit: UIView?) -> String {
                    var items: [String] = []; var v = hit
                    while let item = v {
                        items.append("\(kind(item)):rect=\(item.frame):z=\(item.layer.zPosition):enabled=\(item.isUserInteractionEnabled):hidden=\(item.isHidden):alpha=\(item.alpha)")
                        v = item.superview
                    }
                    return items.joined(separator: " > ")
                }
                NSLog("[DRAWER-AUDIT] owner=\(ObjectIdentifier(self)) menu=\(ObjectIdentifier(self.menu)) updates=\(self.menuUpdateCount) bindingMatches=\(self.auditBindingMatches) busy=\(self.auditBusy) phase=\(self.phase) active=\(self.sceneActive) q=\(self.q) W=\(self.width) accepts=\(self.accepts(p))")
                NSLog("[DRAWER-AUDIT] root=\(self.view.bounds) surface=\(self.surface.bounds) transform=\(self.surface.transform) hostFrame=\(self.menu.view.frame) hostBounds=\(self.menu.view.bounds) local=\(local)")
                NSLog("[DRAWER-AUDIT] hostHit=\(kind(hostHit)) ownerHit=\(kind(ownerHit)) windowHit=\(kind(windowHit)) windowInMenu=\(windowHit?.isDescendant(of: self.menu.view) ?? false)")
                NSLog("[DRAWER-AUDIT] windowChain=\(chain(windowHit))")
                NSLog("[DRAWER-AUDIT] ownerChain=\(chain(ownerHit))")
                if let parent = self.view.superview {
                    NSLog("[DRAWER-AUDIT] siblings=\(parent.subviews.map { kind($0) + ":z=\($0.layer.zPosition):rect=\($0.frame)" }.joined(separator: " | "))")
                }
            }
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard sceneActive else { return false }
        // UIButton/UITextField/UISlider keep their normal touch-up and tracking.
        var candidate = touch.view
        while let current = candidate {
            if current is UIControl { return false }
            candidate = current.superview
        }
        let point = touch.location(in: view)
        guard view.bounds.contains(point) else { return false }
        return q > 0 ? accepts(point) : point.x <= 24 && point.y >= 110
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard sceneActive, let p = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let v = p.velocity(in: view)
        // shouldReceive already checked the touch-down edge, not the moved location.
        return abs(v.x) > abs(v.y) && (q > 0 || v.x > 0)
    }
    @objc func handlePan(_ sender: UIPanGestureRecognizer) {
        guard sceneActive else { return }
        let translation = sender.translation(in: view).x
        let location = sender.location(in: view)
        switch sender.state {
        case .began:
            preservePickup = phase != .closed && phase != .open
            cancelClock(); consumed = false; openingDrag = q < width / 2
            pickupQ = q; pickupOutline = outline; lastTranslation = translation
            fingerCount = sender.numberOfTouches; phase = .manual
            // Keep BOTH actual position and shape at pickup, including the y-dependent curve.
        case .changed:
            guard !consumed, phase == .manual else { return }
            if fingerCount != sender.numberOfTouches {
                fingerCount = sender.numberOfTouches; lastTranslation = translation; return
            }
            let delta = translation - lastTranslation; lastTranslation = translation
            q = min(width, max(0, q + delta)); touchY = min(view.bounds.height, max(0, location.y))
            let next = openingDrag ? manualOutline() : quadratic(c: (width + q)/2, e: width)
            outline = preservePickup ? blend(pickupOutline, next, min(1, abs(q - pickupQ) / max(1, width * 0.12))) : next
            applyFrame()
            if openingDrag && q >= width / 2 {
                // q is first committed at the threshold; sqrt never receives a negative phase.
                consumed = true; request(open: true, velocity: sender.velocity(in: view).x)
            }
        case .ended:
            if consumed { consumed = false; return }
            request(open: false, velocity: sender.velocity(in: view).x, smooth: openingDrag && q < width / 2)
        case .cancelled, .failed:
            // Cancellation restores the intent at pickup, never masquerades as UP.
            consumed = false; request(open: targetOpen)
        default: break
        }
    }
    func accepts(_ point: CGPoint) -> Bool {
        guard q > 0, view.bounds.contains(point) else { return false }
        let local = surface.convert(point, from: view)
        return maskLayer.path?.contains(local) == true
    }
}

private final class DrawerHitView: UIView {
    weak var owner: DrawerRenderOwner?
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let owner, owner.sceneActive, owner.accepts(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// The representable is a zero-size lifecycle anchor, never a full-screen hit host.
/// Its actual drawer is a UIKit child/sibling above the application's content.
private final class DrawerAnchorView: UIView {
    var windowChanged: (() -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); windowChanged?() }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

final class DrawerPortalController: UIViewController {
    let owner = DrawerRenderOwner()
    override func loadView() {
        let anchor = DrawerAnchorView()
        anchor.backgroundColor = .clear; anchor.isUserInteractionEnabled = false
        anchor.windowChanged = { [weak self] in
            guard let self else { return }
            if self.view.window == nil { self.detach() } else { self.attachIfNeeded() }
        }
        view = anchor
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); attachIfNeeded()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews(); attachIfNeeded()
    }
    func attachIfNeeded() {
        guard let window = view.window, let host = window.rootViewController,
              host !== self else { return }
        if owner.parent !== host {
            detach()
            host.addChild(owner)
            host.view.addSubview(owner.view)
            owner.view.frame = window.convert(window.bounds, to: host.view)
            owner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            owner.didMove(toParent: host)
            host.view.addGestureRecognizer(owner.pan)
        }
        owner.view.frame = window.convert(window.bounds, to: host.view)
        // Never raise a retained drawer over UIKit presentation containers.
        owner.view.setNeedsLayout()
    }
    func detach() {
        if owner.isViewLoaded { owner.view.accessibilityViewIsModal = false }
        owner.pan.view?.removeGestureRecognizer(owner.pan)
        owner.cancelClock()
        if owner.parent != nil {
            owner.willMove(toParent: nil)
            owner.view.removeFromSuperview()
            owner.removeFromParent()
        }
    }
}

struct NativeFluidDrawer<Menu: View>: UIViewControllerRepresentable {
    let state: FusionState
    let active: Bool
    let busy: Bool
    let reduceMotion: Bool
    let strength: Double
    let menu: Menu
    func makeUIViewController(context: Context) -> DrawerPortalController {
        let portal = DrawerPortalController(); state.drawerOwner = portal.owner
        portal.owner.loadViewIfNeeded(); return portal
    }
    func updateUIViewController(_ portal: DrawerPortalController, context: Context) {
        let owner = portal.owner
        if ProcessInfo.processInfo.arguments.contains("-DrawerClickAudit") {
            owner.auditBindingMatches = state.drawerOwner === owner
            owner.auditBusy = busy
        }
        owner.reduceMotion = reduceMotion
        if owner.sceneActive != active { owner.setActive(active) }
        owner.updateMenu(AnyView(menu), strength: strength)
        portal.attachIfNeeded()
    }
    static func dismantleUIViewController(_ portal: DrawerPortalController, coordinator: ()) {
        portal.detach(); portal.owner.shutdown()
    }
}

struct FusionAvatarSupport: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(ellipseIn: rect); p.addEllipse(in: rect.insetBy(dx: 9, dy: 9)); return p
    }
}
