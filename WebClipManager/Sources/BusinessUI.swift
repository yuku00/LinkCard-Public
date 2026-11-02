import UIKit
import UniformTypeIdentifiers

// Explicit scene/window ownership, as in Santander's MIT UIKit lifecycle.
// No hosting controller, preferences rebind, root persona or spawn on this path.
final class BusinessSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = BusinessTabs()
        self.window = window
        window.makeKeyAndVisible()
        StartupLog.record("S2_WINDOW_VISIBLE_REQUESTED")
    }
}

final class BusinessTabs: UITabBarController {
    init(repository: Repository = Repository(), notesLoader: @escaping @Sendable () throws -> AppleNotesBatch = { try AppleNotesStore.load() }) {
        super.init(nibName: nil, bundle: nil)
        viewControllers = [BusinessList(mode: .clips, repository: repository, notesLoader: notesLoader),
                           BusinessList(mode: .notes, repository: repository, notesLoader: notesLoader)].map {
            UINavigationController(rootViewController: $0)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

@MainActor
final class BusinessList: UITableViewController, UISearchResultsUpdating, UIDocumentPickerDelegate {
    enum Mode { case clips, notes }
    let mode: Mode
    let repository: Repository
    let notesLoader: @Sendable () throws -> AppleNotesBatch
    private(set) var clips: [Clip] = []
    private(set) var notes: [ImportedNote] = []
    private(set) var busy = false
    private(set) var status = "尚未读取。点击读取按钮开始；不自动访问个人内容。"
    private(set) var readState = "notRead"
    var selected: Set<String> = []
    private let search = UISearchController(searchResultsController: nil)
    private var staging: ExportStaging?
    private var exportButton: UIBarButtonItem!
    private var readButton: UIBarButtonItem!
    private var selectButton: UIBarButtonItem!
    private var clearButton: UIBarButtonItem!
    private var query: String { search.searchBar.text ?? "" }
    var visibleClips: [Clip] { clips.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) } }
    var visibleNotes: [ImportedNote] { notes.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query) } }
    init(mode: Mode, repository: Repository, notesLoader: @escaping @Sendable () throws -> AppleNotesBatch) {
        self.mode = mode; self.repository = repository; self.notesLoader = notesLoader
        super.init(style: .insetGrouped)
        title = mode == .clips ? "书签管理" : "备忘录导出"
        tabBarItem.image = UIImage(systemName: mode == .clips ? "bookmark" : "note.text")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.accessibilityIdentifier = mode == .clips ? "webclipsList" : "notesList"
        navigationController?.navigationBar.prefersLargeTitles = true
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "搜索标题或内容"
        navigationItem.searchController = search
        definesPresentationContext = true
        readButton = UIBarButtonItem(title: "读取", style: .plain, target: self, action: #selector(confirmRead))
        readButton.accessibilityIdentifier = "readItems"
        exportButton = UIBarButtonItem(title: "导出", style: .plain, target: self, action: #selector(confirmExport))
        exportButton.accessibilityIdentifier = "exportItems"
        navigationItem.rightBarButtonItems = [exportButton, readButton]
        selectButton = UIBarButtonItem(title: "选择结果", style: .plain, target: self, action: #selector(selectVisible))
        clearButton = UIBarButtonItem(title: "清除内存", style: .plain, target: self, action: #selector(clearMemory))
        toolbarItems = [selectButton, UIBarButtonItem(systemItem: .flexibleSpace), clearButton]
        navigationController?.setToolbarHidden(false, animated: false)
        update()
    }
    private func update() {
        guard isViewLoaded else { return }
        readButton.isEnabled = !busy
        exportButton.isEnabled = !busy && !selected.isEmpty
        selectButton.isEnabled = !busy
        clearButton.isEnabled = !busy
        tableView.reloadData()
    }
    func updateSearchResults(for searchController: UISearchController) { tableView.reloadData() }
    @objc func selectVisible() {
        let ids = mode == .clips ? visibleClips.map(\.id) : visibleNotes.map { $0.id.uuidString }
        if Set(ids).isSubset(of: selected) { selected.subtract(ids) } else { selected.formUnion(ids) }
        update()
    }
    @objc func clearMemory() {
        guard !busy else { return }
        clips = []; notes = []; selected = []; readState = "notRead"
        status = "已清除内存，不修改源数据。"
        staging = nil
        update()
    }
    @objc func confirmRead() {
        guard !busy else { return }
        let message = mode == .clips ? "只读扫描系统 WebClips。不会删除或修改桌面项目。" : "只读定位 Notes，创建内存一致性快照，解析未锁定正文。跳过锁定、未下载或不支持内容；不下载附件。上限 1000 篇 / 16 MiB，数据库 128 MiB。"
        let alert = UIAlertController(title: "读取确认", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "只读读取", style: .default) { [weak self] _ in
            Task { await self?.loadItems() }
        })
        present(alert, animated: true)
    }
    func loadItems() async {
        guard !busy else { return }
        busy = true; readState = "reading"; status = "正在只读读取…"; update()
        defer { busy = false; update() }
        do {
            if mode == .clips {
                let scan = try await repository.scan()
                clips = scan.clips; selected = []
                readState = scan.issues.isEmpty ? "loaded" : "partial"
                status = "读取 \(clips.count) 项 · 跳过/异常 \(scan.issues.count) 项。删除尚未启用。"
                if let failure = scan.firstFailure { status += "\n" + failure.summary }
            } else {
                let loader = notesLoader
                let batch = try await Task.detached { try loader() }.value
                notes = batch.notes; selected = Set(notes.map { $0.id.uuidString })
                readState = "loaded"; status = batch.summary
            }
        } catch {
            readState = "failed"
            status = "读取失败，保留原批次。\n" + AccessError.capture(error).summary
            if mode == .notes { NotesReadDiagnostic.record(state: "failed", error: error) }
        }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : (mode == .clips ? visibleClips.count : visibleNotes.count)
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "只读 · \(readState)" : "结果 · 已选择 \(selected.count) 项"
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 2
        if indexPath.section == 0 {
            cell.textLabel?.text = status
            cell.textLabel?.font = .preferredFont(forTextStyle: .footnote)
            cell.selectionStyle = .none
            cell.accessibilityIdentifier = "readStatus"
        } else {
            let id: String
            if mode == .clips {
                let clip = visibleClips[indexPath.row]
                id = clip.id; cell.textLabel?.text = clip.title; cell.detailTextLabel?.text = clip.url
                cell.imageView?.image = clip.icon.flatMap { UIImage(data: $0) } ?? UIImage(systemName: "bookmark")
            } else {
                let note = visibleNotes[indexPath.row]
                id = note.id.uuidString; cell.textLabel?.text = note.title; cell.detailTextLabel?.text = note.text
            }
            cell.accessoryType = selected.contains(id) ? .checkmark : .none
            cell.accessibilityIdentifier = "contentRow"
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !busy, indexPath.section == 1 else { return }
        let id = mode == .clips ? visibleClips[indexPath.row].id : visibleNotes[indexPath.row].id.uuidString
        if !selected.insert(id).inserted { selected.remove(id) }
        update()
    }
    @objc func confirmExport() {
        guard !busy, !selected.isEmpty else { return }
        let alert = UIAlertController(title: "导出所选 \(selected.count) 项？", message: "含搜索隐藏项。文件可能包含私人内容；选择云盘可能由系统同步。备忘录仅导出正文，不是完整富文本/附件备份。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        for markdown in (mode == .notes ? [false, true] : [false]) {
            let title = mode == .clips ? "备份所选书签" : (markdown ? "Markdown 原文" : "TXT 原文")
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                Task { await self?.exportSelected(markdown: markdown) }
            })
        }
        present(alert, animated: true)
    }
    // Shared by the real picker path and integration tests; creates only owned files.
    func prepareExport(markdown: Bool) async throws -> ExportStaging {
        let stage = try ExportStaging()
        if mode == .clips {
            let backup = try await repository.backup(ids: Array(selected))
            guard !selected.isEmpty, backup.results.count == selected.count,
                  backup.results.allSatisfy({ $0.message == "已读取完整目录；需完成系统导出才保存到目标位置" }) else {
                throw ClipError.invalid("部分书签备份失败，未导出不完整备份。")
            }
            _ = try stage.write(backup.data, name: "WebClips.webclipbackup")
        } else {
            for (index, note) in notes.filter({ selected.contains($0.id.uuidString) }).enumerated() {
                _ = try stage.write(Data(note.text.utf8), name: NoteFiles.filename(note.title, index: index, markdown: markdown))
            }
        }
        guard !stage.urls.isEmpty else { throw ClipError.invalid("没有可导出项目") }
        return stage
    }
    private func exportSelected(markdown: Bool) async {
        guard !busy else { return }
        busy = true; update()
        defer { busy = false; update() }
        do {
            let stage = try await prepareExport(markdown: markdown)
            staging = stage
            let picker = UIDocumentPickerViewController(forExporting: stage.urls, asCopy: true)
            picker.delegate = self
            present(picker, animated: true)
        } catch {
            status = "导出失败，源数据未修改。" + AccessError.capture(error).summary
        }
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { staging = nil }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        staging = nil
        status = "系统保存操作完成；请在所选位置核对文件。源数据未修改。"
        update()
    }
}
