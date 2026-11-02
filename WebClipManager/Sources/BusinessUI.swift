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
    private let backdrop = UIImageView()
    private let veil = UIView()
    init(repository: Repository = Repository(), notesLoader: @escaping @Sendable () throws -> AppleNotesBatch = { try AppleNotesStore.load() }) {
        super.init(nibName: nil, bundle: nil)
        viewControllers = [BusinessList(mode: .clips, repository: repository, notesLoader: notesLoader),
                           BusinessList(mode: .notes, repository: repository, notesLoader: notesLoader)].map {
            let navigation = UINavigationController(rootViewController: $0)
            navigation.view.backgroundColor = .clear
            return navigation
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        backdrop.frame = view.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backdrop.contentMode = .scaleAspectFill
        backdrop.clipsToBounds = true
        view.insertSubview(backdrop, at: 0)
        veil.frame = view.bounds
        veil.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        veil.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.34)
        view.insertSubview(veil, aboveSubview: backdrop)
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        NotificationCenter.default.addObserver(self, selector: #selector(refreshBackground), name: BackgroundSession.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshBackground), name: UIApplication.didBecomeActiveNotification, object: nil)
        refreshBackground()
    }
    @objc private func refreshBackground() {
        BackgroundSession.loadOnce()
        backdrop.image = BackgroundSession.image
        veil.isHidden = backdrop.image == nil
    }
}

// Images are downsampled before persistence; failed operations never replace the displayed image.
@MainActor
enum BackgroundSession {
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
    static func thumbnail(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 96,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
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

final class ClipGridCell: UICollectionViewCell {
    private let glass = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let urlLabel = UILabel()
    private let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    override init(frame: CGRect) {
        super.init(frame: frame)
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.clipsToBounds = true; glass.layer.cornerRadius = 20; glass.layer.cornerCurve = .continuous
        glass.layer.borderWidth = 1 / UIScreen.main.scale
        contentView.addSubview(glass)
        let header = UIStackView(arrangedSubviews: [iconView, UIView(), check])
        header.axis = .horizontal; header.alignment = .center
        iconView.contentMode = .scaleAspectFit
        iconView.backgroundColor = .tertiarySystemFill; iconView.layer.cornerRadius = 10; iconView.clipsToBounds = true
        check.tintColor = .systemBlue; check.contentMode = .scaleAspectFit
        titleLabel.font = .preferredFont(forTextStyle: .headline); titleLabel.adjustsFontForContentSizeCategory = true; titleLabel.numberOfLines = 2
        urlLabel.font = .preferredFont(forTextStyle: .caption1); urlLabel.adjustsFontForContentSizeCategory = true; urlLabel.textColor = .secondaryLabel; urlLabel.numberOfLines = 2
        let stack = UIStackView(arrangedSubviews: [header, titleLabel, urlLabel])
        stack.axis = .vertical; stack.spacing = 6; stack.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), glass.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            glass.topAnchor.constraint(equalTo: contentView.topAnchor), glass.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: glass.contentView.topAnchor, constant: 12), stack.bottomAnchor.constraint(lessThanOrEqualTo: glass.contentView.bottomAnchor, constant: -12),
            iconView.widthAnchor.constraint(equalToConstant: 44), iconView.heightAnchor.constraint(equalToConstant: 44),
            check.widthAnchor.constraint(equalToConstant: 22), check.heightAnchor.constraint(equalToConstant: 22)
        ])
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func configure(_ clip: Clip, selected: Bool) {
        iconView.image = clip.icon.flatMap { GlassCell.thumbnail($0) } ?? UIImage(systemName: "bookmark")
        titleLabel.text = clip.title; urlLabel.text = clip.url
        check.isHidden = !selected
        glass.layer.borderColor = (selected ? UIColor.systemBlue : UIColor.separator).resolvedColor(with: traitCollection).cgColor
        glass.layer.borderWidth = selected ? 2 : 1 / UIScreen.main.scale
        accessibilityLabel = "\(clip.title)，\(clip.url)"
        accessibilityValue = selected ? "已选中" : "未选中"
        accessibilityTraits = selected ? [.button, .selected] : .button
        accessibilityIdentifier = "contentRow"
    }
}

final class ClipGridRow: UITableViewCell {
    let grid: UICollectionView
    let height: NSLayoutConstraint
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 10; layout.minimumLineSpacing = 10
        grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
        height = grid.heightAnchor.constraint(equalToConstant: 150)
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear; selectionStyle = .none
        grid.backgroundColor = .clear; grid.isScrollEnabled = false
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.register(ClipGridCell.self, forCellWithReuseIdentifier: "clip")
        grid.accessibilityIdentifier = "webclipsGridRow"
        contentView.addSubview(grid)
        NSLayoutConstraint.activate([grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            grid.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5), height])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

@MainActor
final class BusinessList: UITableViewController, UISearchResultsUpdating, UIDocumentPickerDelegate, PHPickerViewControllerDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    enum Mode { case clips, notes }
    let mode: Mode
    let repository: Repository
    let notesLoader: @Sendable () throws -> AppleNotesBatch
    private(set) var clips: [Clip] = []
    private(set) var notes: [ImportedNote] = []
    private(set) var busy = false
    private(set) var status = "尚未读取。"
    private var hasAttemptedInitialRead = false
    private(set) var readState = "notRead"
    var selected: Set<String> = []
    let search = UISearchController(searchResultsController: nil)
    private var staging: ExportStaging?
    private var backgroundPicker: UIDocumentPickerViewController?
    private var exportButton: UIBarButtonItem!
    private var readButton: UIBarButtonItem!
    enum ScreenFilter { case all, full, nonFull }
    var screenFilter: ScreenFilter = .all
    var duplicatesOnly = false
    private var menuButton: UIBarButtonItem!
    private var lastGridWidth: CGFloat = 0
    var gridColumns: Int { traitCollection.preferredContentSizeCategory.isAccessibilityCategory || tableView.bounds.width < 320 ? 1 : 2 }
    private var gridItemHeight: CGFloat {
        let head = UIFont.preferredFont(forTextStyle: .headline).lineHeight
        let sub = UIFont.preferredFont(forTextStyle: .caption1).lineHeight
        return ceil(44 + 12 + 2 * head + 2 * sub + 24)
    }
    private var query: String { search.searchBar.text ?? "" }
    var visibleClips: [Clip] {
        let duplicates = duplicatesOnly ? Repository.duplicateIDs(clips) : []
        return clips.filter { clip in
            let matchesQuery = query.isEmpty || clip.title.localizedCaseInsensitiveContains(query) || clip.url.localizedCaseInsensitiveContains(query) || clip.id.localizedCaseInsensitiveContains(query)
            let matchesScreen = screenFilter == .all || (screenFilter == .full && clip.fullScreen) || (screenFilter == .nonFull && !clip.fullScreen)
            return matchesQuery && matchesScreen && (!duplicatesOnly || duplicates.contains(clip.id))
        }
    }
    var visibleNotes: [ImportedNote] { notes.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query) } }
    init(mode: Mode, repository: Repository, notesLoader: @escaping @Sendable () throws -> AppleNotesBatch) {
        self.mode = mode; self.repository = repository; self.notesLoader = notesLoader
        self.status = mode == .clips ? "即将只读读取书签…" : "尚未读取。点击读取按钮开始。"
        super.init(style: .insetGrouped)
        title = mode == .clips ? "书签管理" : "备忘录导出"
        tabBarItem.image = UIImage(systemName: mode == .clips ? "bookmark" : "note.text")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.accessibilityIdentifier = mode == .clips ? "webclipsList" : "notesList"
        navigationController?.navigationBar.prefersLargeTitles = true
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
        navigationController?.navigationBar.standardAppearance = navAppearance
        navigationController?.navigationBar.scrollEdgeAppearance = navAppearance
        navigationController?.navigationBar.compactAppearance = navAppearance
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.separatorStyle = .none
        tableView.register(GlassCell.self, forCellReuseIdentifier: "glass")
        tableView.register(ClipGridRow.self, forCellReuseIdentifier: "gridRow")
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
        menuButton = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: UIMenu(title: "", children: []))
        menuButton.accessibilityLabel = "筛选与批量操作"
        navigationItem.rightBarButtonItems = [menuButton, exportButton, readButton]
        navigationController?.setToolbarHidden(true, animated: false)
        update()
    }
    @objc private func refreshBackground() {
        BackgroundSession.loadOnce()
        tableView.backgroundView = nil
        tableView.backgroundColor = .clear
        tableView.reloadData()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard mode == .clips, !hasAttemptedInitialRead else { return }
        hasAttemptedInitialRead = true
        Task { [weak self] in
            guard let self = self, self.readState == "notRead", !self.busy else { return }
            await self.loadItems()
        }
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
    private var visibleIDs: Set<String> {
        Set(mode == .clips ? visibleClips.map(\.id) : visibleNotes.map { $0.id.uuidString })
    }
    private var hiddenSelectionCount: Int { selected.subtracting(visibleIDs).count }
    private func update() {
        guard isViewLoaded, readButton != nil, exportButton != nil, menuButton != nil else { return }
        readButton.isEnabled = !busy
        exportButton.isEnabled = !busy && !selected.isEmpty
        let disabled: UIMenuElement.Attributes = busy ? .disabled : []
        var actions: [UIMenuElement] = []
        if mode == .clips {
            let filters: [(String, ScreenFilter)] = [("全部", .all), ("全屏", .full), ("非全屏", .nonFull)]
            let screenActions = filters.map { title, filter in
                UIAction(title: title, attributes: disabled, state: screenFilter == filter ? .on : .off) { [weak self] _ in self?.screenFilter = filter; self?.update() }
            }
            actions.append(UIMenu(title: "显示模式", options: .displayInline, children: screenActions))
            actions.append(UIAction(title: "测试书签：仅备份（不删除）", attributes: busy || selected.count != 1 ? .disabled : []) { [weak self] _ in
                self?.confirmTestBackup()
            })
            actions.append(UIAction(title: "回收站", attributes: disabled) { [weak self] _ in self?.showRecycle() })
            actions.append(UIAction(title: "精确重复 URL", attributes: disabled, state: duplicatesOnly ? .on : .off) { [weak self] _ in
                guard let self = self else { return }; self.duplicatesOnly.toggle(); self.update()
            })
        }
        actions.append(UIAction(title: "选择全部当前结果（\(visibleIDs.count)）", attributes: busy || visibleIDs.isEmpty ? .disabled : []) { [weak self] _ in
            guard let self = self else { return }; self.selected.formUnion(self.visibleIDs); self.update()
        })
        actions.append(UIAction(title: "清除全部选择（\(selected.count)）", attributes: busy || selected.isEmpty ? .disabled : []) { [weak self] _ in
            self?.selected.removeAll(); self?.update()
        })
        actions.append(UIAction(title: "清除读取结果", attributes: busy ? .disabled : []) { [weak self] _ in self?.confirmClearMemory() })
        menuButton.menu = UIMenu(title: "筛选与批量操作", children: actions)
        tableView.reloadData()
    }
    func updateSearchResults(for searchController: UISearchController) { update() }
    private func showRecycle() {
        do {
            let entries = try RecycleStore.entries()
            let alert = UIAlertController(title: "回收站（\(entries.count)）", message: "仅应用专属副本；无完整清单的条目只能清理。恢复不覆盖现有目录，不保证图标注册、布局或登录状态。", preferredStyle: .actionSheet)
            for (index, entry) in entries.enumerated() {
                alert.addAction(UIAlertAction(title: entry.identifier == nil ? "未完成副本 \(index + 1)" : "副本 \(index + 1)", style: .default) { [weak self] _ in self?.showRecycleEntry(entry) })
            }
            if !entries.isEmpty {
                alert.addAction(UIAlertAction(title: "清空专属回收副本…", style: .destructive) { [weak self] _ in self?.confirmRecycleClear(entries, second: false) })
            }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            if let pop = alert.popoverPresentationController { pop.barButtonItem = menuButton }
            present(alert, animated: true)
        } catch { recycleMessage("无法打开回收站", error.localizedDescription) }
    }
    private func showRecycleEntry(_ entry: RecycleStore.Entry) {
        let alert = UIAlertController(title: "回收副本", message: entry.identifier == nil ? "清单不完整，只能清理。" : "恢复仅复制文件，不覆盖已有目录；不保证图标注册、布局或登录状态。", preferredStyle: .alert)
        if entry.identifier != nil {
            alert.addAction(UIAlertAction(title: "无覆盖恢复", style: .default) { [weak self] _ in
                do { try RecycleStore.restore(entry.name); self?.recycleMessage("文件已恢复", "未验证桌面图标注册、布局或登录状态。") }
                catch { self?.recycleMessage("恢复失败", error.localizedDescription) }
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    private func confirmRecycleClear(_ entries: [RecycleStore.Entry], second: Bool) {
        let alert = UIAlertController(title: second ? "再次确认永久清空？" : "清空回收副本？", message: "仅清理应用专属回收目录内 \(entries.count) 个副本（含未完成项），不操作源书签或 Safari。此操作不可撤销。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: second ? "永久清空" : "继续", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            if !second { self.confirmRecycleClear(entries, second: true); return }
            var failed = 0
            for entry in entries { do { try RecycleStore.remove(entry.name) } catch { failed += 1 } }
            self.recycleMessage("清理结束", "失败 \(failed) 项；源书签和 Safari 未由此操作修改。")
        })
        present(alert, animated: true)
    }
    private func recycleMessage(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default)); present(alert, animated: true)
    }
    private func confirmTestBackup() {
        guard selected.count == 1, let id = selected.first, let clip = clips.first(where: { $0.id == id }), clip.title == "WCM-DELETE-TEST" else {
            let alert = UIAlertController(title: "仅限测试书签", message: "请先新建一个标题精确为 WCM-DELETE-TEST 的可丢弃主屏幕书签，重新读取并仅选择该项。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .cancel)); present(alert, animated: true); return
        }
        let alert = UIAlertController(title: "备份可丢弃测试书签？", message: "只复制到本机应用专属回收目录，不删除系统书签或修改 Safari。可在回收站中恢复或清理副本。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "仅备份", style: .default) { [weak self] _ in
            guard let self = self, !self.busy else { return }
            self.busy = true; self.status = "正在备份测试书签…"; self.update()
            Task { [weak self] in
                let result = await Task.detached { Result { try RecycleStore.backupTest(clip) } }.value
                guard let self = self else { return }
                self.busy = false
                switch result {
                case .success: self.status = "测试书签备份完成（backupOnly）；未删除源，也未验证桌面登记。"
                case .failure(let error): self.status = "备份失败：\(error.localizedDescription)"
                }
                self.update()
            }
        })
        present(alert, animated: true)
    }
    private func confirmClearMemory() {
        let alert = UIAlertController(title: "清除读取结果？", message: "仅清除当前内存中的读取结果和选择，不修改系统书签或备忘录。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除读取结果", style: .destructive) { [weak self] _ in self?.clearMemory() })
        present(alert, animated: true)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = tableView.bounds.width
        if abs(width - lastGridWidth) > 0.5 { lastGridWidth = width; tableView.reloadData() }
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory { update() }
    }
    @objc func selectVisible() {
        let ids = mode == .clips ? visibleClips.map(\.id) : visibleNotes.map { $0.id.uuidString }
        selected.formUnion(ids)
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
        if mode == .clips { hasAttemptedInitialRead = true }
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
        section == 0 ? 1 : (mode == .clips ? max(1, (visibleClips.count + gridColumns - 1) / gridColumns) : max(1, visibleNotes.count))
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "只读 · \(readState)" : "显示 \(visibleIDs.count) 项 · 已选 \(selected.count) 项 · 隐藏已选 \(hiddenSelectionCount) 项"
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 1 && mode == .clips && !visibleClips.isEmpty {
            let cell = tableView.dequeueReusableCell(withIdentifier: "gridRow", for: indexPath) as! ClipGridRow
            cell.grid.tag = indexPath.row
            cell.grid.dataSource = self; cell.grid.delegate = self
            cell.height.constant = gridItemHeight
            cell.grid.collectionViewLayout.invalidateLayout()
            cell.grid.reloadData()
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "glass", for: indexPath) as! GlassCell
        if indexPath.section == 0 {
            cell.configure(title: status, subtitle: nil, icon: nil, selected: false, status: true)
            cell.accessibilityIdentifier = "readStatus"
        } else if mode == .clips || visibleNotes.isEmpty {
            let hasData = mode == .clips ? !clips.isEmpty : !notes.isEmpty
            cell.configure(title: hasData ? "没有匹配结果" : "暂无读取结果", subtitle: hasData ? "尝试调整搜索或筛选。隐藏选择仍会保留。" : "点击页头读取；读取失败不代表源数据为空。", icon: nil, selected: false, status: true)
        } else {
            let note = visibleNotes[indexPath.row]
            cell.configure(title: note.title, subtitle: note.text, icon: nil, selected: selected.contains(note.id.uuidString))
            cell.accessibilityIdentifier = "contentRow"
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !busy, indexPath.section == 1, mode == .notes, !visibleNotes.isEmpty else { return }
        toggleSelection(visibleNotes[indexPath.row].id.uuidString)
    }
    private func toggleSelection(_ id: String) {
        if !selected.insert(id).inserted { selected.remove(id) }
        update()
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { max(0, min(gridColumns, visibleClips.count - collectionView.tag * gridColumns)) }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "clip", for: indexPath) as! ClipGridCell
        let clip = visibleClips[collectionView.tag * gridColumns + indexPath.item]
        cell.configure(clip, selected: selected.contains(clip.id))
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !busy else { return }; toggleSelection(visibleClips[collectionView.tag * gridColumns + indexPath.item].id)
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let columns = gridColumns
        return CGSize(width: floor((collectionView.bounds.width - CGFloat(columns - 1) * 10) / CGFloat(columns)), height: gridItemHeight)
    }
    @objc func confirmExport() {
        guard !busy, !selected.isEmpty else { return }
        let alert = UIAlertController(title: "导出所选 \(selected.count) 项？", message: "共 \(selected.count) 项，含隐藏已选 \(hiddenSelectionCount) 项。文件可能包含私人内容；选择云盘可能由系统同步。备忘录仅导出正文，不是完整富文本/附件备份。", preferredStyle: .alert)
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
