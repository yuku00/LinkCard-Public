import UIKit
import SwiftUI

final class StartupDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        StartupLog.record("S1_DID_FINISH_LAUNCHING")
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = StartupViewController()
        self.window = window
        window.makeKeyAndVisible()
        StartupLog.record("S2_WINDOW_VISIBLE_REQUESTED")
        return true
    }
}

final class StartupViewController: UIViewController {
    let logView = UITextView()
    let diagnosticsButton = UIButton(type: .system)
    let copyButton = UIButton(type: .system)
    let openButton = UIButton(type: .system)
    private var diagnosticText = "尚未采集运行权限。"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let title = UILabel()
        title.text = "UIKit 首页 · build 8（恢复系统容器）"
        title.font = .preferredFont(forTextStyle: .title2)
        title.numberOfLines = 0
        let detail = UILabel()
        detail.text = "先采集并复制诊断，再打开主界面一次。\n诊断只查询自身权限和固定目录 open/元数据，不枚举目录或读取书签、备忘录内容。\n仅当前进程内存；重启后无法取得之前的崩溃日志。"
        detail.numberOfLines = 0
        detail.font = .preferredFont(forTextStyle: .footnote)
        diagnosticsButton.setTitle("① 采集运行权限与固定路径诊断", for: .normal)
        diagnosticsButton.addTarget(self, action: #selector(captureDiagnostics), for: .touchUpInside)
        copyButton.setTitle("② 复制当前日志与诊断", for: .normal)
        copyButton.addTarget(self, action: #selector(copyLog), for: .touchUpInside)
        openButton.setTitle("③ 打开主界面（不自动读取）", for: .normal)
        openButton.addTarget(self, action: #selector(openInterface), for: .touchUpInside)
        logView.isEditable = false
        logView.isSelectable = true
        logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logView.accessibilityIdentifier = "startupMemoryLog"
        let stack = UIStackView(arrangedSubviews: [title, detail, diagnosticsButton, copyButton, openButton, logView])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            logView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
        ])
        refreshLog()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        StartupLog.record("S3_UIKIT_DID_APPEAR")
        refreshLog()
    }
    private func refreshLog() {
        logView.text = StartupLog.exportText + "\n\n" + diagnosticText
    }
    @objc func captureDiagnostics() {
        // Only this explicit user action resolves private symbols and probes paths.
        struct Report: Encodable {
            let build: Int
            let scope: String
            let runtime: RuntimePermissions?
            let fixedPaths: AccessSnapshot
            let localPaths: LocalPathDiagnostics
            let storageStatus: String
        }
        let report = Report(build: 8, scope: "current-process-only; no directory enumeration or file contents",
                            runtime: RuntimePermissions.capture(), fixedPaths: ReadAccess.diagnostics(),
                            localPaths: LocalPathDiagnostics.capture(), storageStatus: AppPaths.preparationStatus)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { diagnosticText = String(decoding: try encoder.encode(report), as: UTF8.self) }
        catch { diagnosticText = "diagnosticEncodingFailed" }
        refreshLog()
    }
    @objc func copyLog() {
        refreshLog()
        UIPasteboard.general.string = logView.text
    }
    @objc func openInterface() {
        guard presentedViewController == nil else { return }
        // OS paths are validated, never changed. Invalid paths disable file export,
        // but do not block the independent UIKit diagnostics or in-memory UI.
        AppPaths.prepare()
        diagnosticText += "\nStorage: " + AppPaths.preparationStatus
        StartupLog.record("S4_SWIFTUI_REQUESTED")
        refreshLog()
        let host = UIHostingController(rootView: RootView())
        StartupLog.record("S5_HOST_CREATED")
        refreshLog()
        present(host, animated: true) { [weak self] in
            StartupLog.record("S7_PRESENT_COMPLETED")
            self?.refreshLog()
        }
    }
}
