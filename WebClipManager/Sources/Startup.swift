import UIKit
import SwiftUI

final class StartupDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        StartupLog.record("S1_DID_FINISH_LAUNCHING")
        StartupLog.record("OS " + ProcessInfo.processInfo.operatingSystemVersionString)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = StartupViewController()
        self.window = window
        window.makeKeyAndVisible()
        StartupLog.record("S2_WINDOW_VISIBLE_REQUESTED")
        return true
    }
}

final class StartupViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let title = UILabel()
        title.text = "UIKit 启动成功 · build 3"
        title.font = .preferredFont(forTextStyle: .title2)
        title.numberOfLines = 0
        let detail = UILabel()
        detail.text = "\(ProcessInfo.processInfo.operatingSystemVersionString)\n\n尚未实例化 SwiftUI，也没有读取书签或备忘录。\n\n① 打开原界面（不自动读取）\n② 界面出现后，点右上角刷新手动读取 WebClips。\n若退出，重新打开此页导出日志。"
        detail.numberOfLines = 0
        detail.font = .preferredFont(forTextStyle: .body)
        let open = UIButton(type: .system)
        open.setTitle("① 打开 SwiftUI（不读取）", for: .normal)
        open.addTarget(self, action: #selector(openInterface), for: .touchUpInside)
        let export = UIButton(type: .system)
        export.setTitle("导出启动阶段日志", for: .normal)
        export.addTarget(self, action: #selector(exportLog), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [title, detail, open, export])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        StartupLog.record("S3_UIKIT_DID_APPEAR")
    }
    @objc private func openInterface() {
        StartupLog.record("S4_SWIFTUI_REQUESTED")
        let host = UIHostingController(rootView: RootView())
        StartupLog.record("S5_HOST_CREATED")
        present(host, animated: true) { StartupLog.record("S7_PRESENT_COMPLETED") }
    }
    @objc private func exportLog() {
        let controller = UIActivityViewController(activityItems: [StartupLog.url], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = view
        controller.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(controller, animated: true)
    }
}
