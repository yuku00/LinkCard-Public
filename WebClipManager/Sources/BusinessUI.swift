import UIKit
import UniformTypeIdentifiers
import PhotosUI
import ImageIO

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

// Images are downsampled before persistence; failed operations never replace the displayed image.
@MainActor
private enum BackgroundSession {
    static var image: UIImage?
    static let store = BackgroundStore()
    static var loaded = false
    static let changed = Notification.Name("BusinessBackgroundChanged")
    static func loadOnce() {
        guard !loaded else { return }
        do {
            if let data = try store.load() {
                guard let decoded = UIImage(data: data) else { return }
                image = decoded
            }
            loaded = true
        } catch { /* Protected data may be unavailable until first unlock; retry on activation. */ }
    }
    static func set(_ image: UIImage) throws {
        guard let data = image.jpegData(compressionQuality: 0.85) else { throw BackgroundError.invalidImage }
        try store.save(data)
        self.image = image; loaded = true
        NotificationCenter.default.post(name: changed, object: nil)
    }
    static func reset() throws {
        try store.reset()
        image = nil; loaded = true
        NotificationCenter.default.post(name: changed, object: nil)
    }
    nonisolated static func decode(_ url: URL) throws -> UIImage {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 12 * 1024 * 1024,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw BackgroundError.invalidImage }
        return UIImage(cgImage: image)
    }
    enum BackgroundError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "请选择不超过 12 MB 的有效图片。" }
    }
}

final class GlassCell: UITableViewCell {
    private let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    let iconContainer = UIView()
    let iconView = UIImageView()
    private let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    private let textStack = UIStackView()
    private let row = UIStackView()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .default
        card.translatesAutoresizingMaskIntoConstraints = false
        card.clipsToBounds = true
        card.layer.cornerRadius = 20
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1 / UIScreen.main.scale
        card.layer.borderColor = UIColor.separator.cgColor
        contentView.addSubview(card)
        row.axis = .horizontal; row.alignment = .center; row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(row)
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = .tertiarySystemFill
        iconContainer.layer.cornerRadius = 10; iconContainer.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.isAccessibilityElement = false
        iconContainer.addSubview(iconView)
        textStack.axis = .vertical; textStack.spacing = 6
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true; titleLabel.numberOfLines = 0
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true; subtitleLabel.numberOfLines = 2
        subtitleLabel.textColor = .secondaryLabel
        textStack.addArrangedSubview(titleLabel); textStack.addArrangedSubview(subtitleLabel)
        check.tintColor = .systemBlue; check.contentMode = .scaleAspectFit
        check.isAccessibilityElement = false
        row.addArrangedSubview(iconContainer); row.addArrangedSubview(textStack); row.addArrangedSubview(check)
        let iconWidth = iconContainer.widthAnchor.constraint(equalToConstant: 44)
        let checkWidth = check.widthAnchor.constraint(equalToConstant: 22)
        iconWidth.priority = .defaultHigh; checkWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            row.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 16),
            row.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -16),
            iconWidth,
            iconContainer.heightAnchor.constraint(equalToConstant: 44),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            checkWidth,
            check.heightAnchor.constraint(equalToConstant: 22)
        ])
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func configure(title: String, subtitle: String?, icon: UIImage?, selected: Bool, status: Bool = false) {
        titleLabel.text = title; subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        iconContainer.isHidden = icon == nil; iconView.image = icon
        check.isHidden = !selected
        titleLabel.font = .preferredFont(forTextStyle: status ? .footnote : .headline)
        accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = selected ? [.button, .selected] : (status ? .staticText : .button)
        selectionStyle = status ? .none : .default
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        card.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }
    override func prepareForReuse() {
        super.prepareForReuse()
        configure(title: "", subtitle: nil, icon: nil, selected: false)
        accessibilityIdentifier = nil
    }
}

@MainActor
final class BusinessList: UITableViewController, UISearchResultsUpdating, UIDocumentPickerDelegate, PHPickerViewControllerDelegate {
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
    private var backgroundPicker: UIDocumentPickerViewController?
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
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.separatorStyle = .none
        tableView.register(GlassCell.self, forCellReuseIdentifier: "glass")
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "paintpalette"), menu: UIMenu(title: "自定义背景", children: [
            UIAction(title: "从照片选择", image: UIImage(systemName: "photo")) { [weak self] _ in self?.choosePhoto() },
            UIAction(title: "从文件选择", image: UIImage(systemName: "folder")) { [weak self] _ in self?.chooseFile() },
            UIAction(title: "恢复默认背景", image: UIImage(systemName: "arrow.counterclockwise")) { [weak self] _ in
                do { try BackgroundSession.reset() } catch { self?.showBackgroundError(error) }
            }
        ]))
        navigationItem.leftBarButtonItem?.accessibilityLabel = "设置持久背景"
        NotificationCenter.default.addObserver(self, selector: #selector(refreshBackground), name: BackgroundSession.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshBackground), name: UIApplication.didBecomeActiveNotification, object: nil)
        BackgroundSession.loadOnce()
        refreshBackground()
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
    @objc private func refreshBackground() {
        BackgroundSession.loadOnce()
        let background = UIView(frame: tableView.bounds)
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        background.backgroundColor = .systemGroupedBackground
        if let image = BackgroundSession.image {
            let imageView = UIImageView(image: image)
            imageView.frame = background.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            background.addSubview(imageView)
            // One translucent veil behind the glass cards avoids stacked live blurs.
            let veil = UIView(frame: background.bounds)
            veil.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.34)
            veil.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            background.addSubview(veil)
        }
        tableView.backgroundView = background
        tableView.reloadData()
    }
    private func choosePhoto() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }
    private func chooseFile() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
        picker.delegate = self
        backgroundPicker = picker
        present(picker, animated: true)
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            showBackgroundError(BackgroundSession.BackgroundError.invalidImage); return
        }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, error in
            // The provider owns this temporary URL; decode before the callback returns.
            let result: Result<UIImage, Error> = Result {
                if let error = error { throw error }
                guard let url = url else { throw BackgroundSession.BackgroundError.invalidImage }
                return try BackgroundSession.decode(url)
            }
            DispatchQueue.main.async { self?.acceptBackground(result) }
        }
    }
    private func acceptBackground(_ result: Result<UIImage, Error>) {
        switch result {
        case .success(let image):
            do { try BackgroundSession.set(image) } catch { showBackgroundError(error) }
        case .failure(let error): showBackgroundError(error)
        }
    }
    private func showBackgroundError(_ error: Error) {
        let alert = UIAlertController(title: "无法保存背景", message: "原背景保持不变。\n" + error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "glass", for: indexPath) as! GlassCell
        if indexPath.section == 0 {
            cell.configure(title: status, subtitle: nil, icon: nil, selected: false, status: true)
            cell.accessibilityIdentifier = "readStatus"
        } else if mode == .clips {
            let clip = visibleClips[indexPath.row]
            let icon = clip.icon.flatMap { UIImage(data: $0) } ?? UIImage(systemName: "bookmark")
            cell.configure(title: clip.title, subtitle: clip.url, icon: icon, selected: selected.contains(clip.id))
            cell.accessibilityIdentifier = "contentRow"
        } else {
            let note = visibleNotes[indexPath.row]
            cell.configure(title: note.title, subtitle: note.text, icon: nil, selected: selected.contains(note.id.uuidString))
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
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        if controller === backgroundPicker { backgroundPicker = nil } else { staging = nil }
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if controller === backgroundPicker {
            backgroundPicker = nil
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            acceptBackground(Result { try BackgroundSession.decode(url) })
            return
        }
        staging = nil
        status = "系统保存操作完成；请在所选位置核对文件。源数据未修改。"
        update()
    }
}
