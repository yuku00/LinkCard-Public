import Foundation

// Markdown destinations preserve existing valid percent escapes and URL delimiters.
enum ObsidianExport {
    static func label(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            if CharacterSet.newlines.contains(scalar) || CharacterSet.controlCharacters.contains(scalar) { result += " "; continue }
            if scalar == "&" { result += "&amp;"; continue }
            if scalar.isASCII && (33...126).contains(scalar.value) && !CharacterSet.alphanumerics.contains(scalar) { result += "\\" }
            result.unicodeScalars.append(scalar)
        }
        return result.isEmpty ? "无标题" : result
    }
    static func destination(_ value: String) -> String {
        let bytes = Array(value.utf8)
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'*+,;=".utf8)
        func hex(_ b: UInt8) -> Bool { (48...57).contains(b) || (65...70).contains(b) || (97...102).contains(b) }
        var result = "", i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == 37 && i + 2 < bytes.count && hex(bytes[i+1]) && hex(bytes[i+2]) {
                result += String(decoding: bytes[i...i+2], as: UTF8.self); i += 3; continue
            }
            if b == 38 { result += "\\&" }
            else if allowed.contains(b) { result.append(Character(UnicodeScalar(b))) }
            else { result += String(format: "%%%02X", b) }
            i += 1
        }
        return result
    }
    static func bookmarks(_ items: [(title: String, url: String)]) -> String {
        var result = "# 书签\n\n"
        for item in items {
            let name = label(item.title)
            if item.url.isEmpty { result += "- \(name)（无 URL）\n" }
            else { result += "- [\(name)](\(destination(item.url)))\n" }
        }
        return result
    }
    static func filename(_ title: String, index: Int, markdown: Bool) -> String {
        let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:*?\"<>|"))
        let clean = title.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        var short = ""
        for scalar in (clean.isEmpty ? "备忘录" : clean).unicodeScalars {
            if short.utf8.count + scalar.utf8.count > 120 { break }
            short.unicodeScalars.append(scalar)
        }
        return String(format: "%03d-", index + 1) + short + (markdown ? ".md" : ".txt")
    }
}
