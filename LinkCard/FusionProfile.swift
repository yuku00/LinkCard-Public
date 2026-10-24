// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import PhotosUI
import ImageIO

final class FusionProfileStore: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published var message: String?
    private var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FusionProfile", isDirectory: true).appendingPathComponent("avatar.jpg")
    }
    init() { if let data = try? Data(contentsOf: url) { image = UIImage(data: data) } }
    func install(_ data: Data) throws {
        guard data.count <= 40 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary), let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.86)
        else { throw CardError.message("无法读取头像，请选择小于 40 MiB 的图片。") }
        var folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true; try folder.setResourceValues(resource)
        try jpeg.write(to: url, options: [.atomic, .completeFileProtection]); image = UIImage(data: jpeg)
    }
    func reset() {
        do { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }; image = nil }
        catch { message = error.localizedDescription }
    }
}
struct FusionAvatar: View {
    let image: UIImage?
    var body: some View {
        GeometryReader { geo in
            Group {
                if let image = image { Image(uiImage: image).resizable().scaledToFill() }
                else {
                    ZStack {
                        LinearGradient(colors: [Color(red: 0.89, green: 0.73, blue: 0.66), Color(red: 0.60, green: 0.56, blue: 0.72), Color(red: 0.32, green: 0.49, blue: 0.57)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text("L").font(.system(size: geo.size.height * 0.55, weight: .medium, design: .serif)).italic().foregroundStyle(.white)
                    }
                }
            }.frame(width: geo.size.width, height: geo.size.height).clipShape(Circle())
        }
    }
}
struct FusionProfileView: View {
    @ObservedObject var store: FusionProfileStore
    @AppStorage("fusion.profile.name.v1") private var name = "我的个人卡"
    @State private var selected: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { Spacer(); FusionAvatar(image: store.image).frame(width: 96, height: 96); Spacer() }
                    TextField("本地显示名称", text: $name).onChange(of: name) { value in if value.count > 80 { name = String(value.prefix(80)) } }
                    PhotosPicker(selection: $selected, matching: .images) { Label("替换头像", systemImage: "photo") }
                    Button("恢复原创 L 头像", role: .destructive) { store.reset() }
                    if let message = store.message { Text(message).foregroundStyle(.red) }
                } footer: { Text("个人信息只保存在本机，不创建账号、不登录、不上传。头像不会进入 NFC 图像。") }
            }.navigationTitle("个人资料").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.accessibilityIdentifier("profile.done") } }
        }.task(id: selected) {
            guard let selected = selected else { return }
            do {
                guard let data = try await selected.loadTransferable(type: Data.self) else { throw CardError.message("未读取到图片") }
                try Task.checkCancellation(); try store.install(data); store.message = nil
            } catch is CancellationError {} catch { store.message = error.localizedDescription }
        }
    }
}
