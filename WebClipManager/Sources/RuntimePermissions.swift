import Foundation

struct RuntimePermissions: Codable {
    struct Check: Codable { let result: Int; let errno: Int }
    let entitlementAPI: String
    let entitlements: [String: String]
    let expectedComparison: [String: String]
    let sandboxAPI: String
    let sandboxChecks: [String: Check]
    static func capture() -> RuntimePermissions? {
        try? JSONDecoder().decode(Self.self, from: Data(WCMRuntimeJSON().utf8))
    }
}

struct LocalPathDiagnostics: Codable {
    let dedicatedStorageReady: Bool
    let homeMatches: Bool
    let documentsMatch: Bool
    let temporaryMatches: Bool
    let applicationUsesUserDefaults: Bool
    static func capture() -> Self {
        Self(dedicatedStorageReady: AppPaths.ready,
             homeMatches: URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path == AppPaths.root.path,
             documentsMatch: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.resolvingSymlinksInPath().path == AppPaths.documents.path,
             temporaryMatches: FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path == AppPaths.temporary.path,
             applicationUsesUserDefaults: false)
    }
}
