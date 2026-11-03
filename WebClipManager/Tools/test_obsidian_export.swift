import Foundation

@main struct TestObsidianExport {
    static func main() {
        let title = "[a] (b) !\\\n<&copy;"
        let url = "https://例子.test/a(b) c/😀?x=1&copy;=2%20z"
        let doc = ObsidianExport.bookmarks([(title, url), ("empty", ""), ("custom", "shortcuts://run?a=b")])
        precondition(doc.contains("[\\[a\\] \\(b\\) \\!\\\\ &lt;" ) == false) // '<' is backslash escaped, not HTML-encoded
        precondition(doc.contains("\\[a\\] \\(b\\) \\!\\\\ \\<&amp;copy\\;"))
        precondition(doc.contains("https://%E4%BE%8B%E5%AD%90.test/a%28b%29%20c/%F0%9F%98%80?x=1\\&copy;=2%20z"))
        precondition(doc.contains("empty（无 URL）") && doc.contains("shortcuts://run?a=b"))
        precondition(!doc.contains("unselected-secret"))
        let a = ObsidianExport.filename("../中/\\:\n" + String(repeating: "😀", count: 200), index: 0, markdown: true)
        let b = ObsidianExport.filename("../中/\\:\n" + String(repeating: "😀", count: 200), index: 1, markdown: true)
        precondition(a != b && !a.contains("/") && !a.contains("\\") && a.utf8.count < 255)
        precondition(ObsidianExport.bookmarks([]) == "# 书签\n\n")
        let huge = String(repeating: "文字\n", count: 200_000)
        precondition(String(data: Data(huge.utf8), encoding: .utf8) == huge)
        precondition(ObsidianExport.destination("x%zz(y) ") == "x%25zz%28y%29%20")
        print("PASS synthetic Markdown, URI, filenames, empty URL, custom scheme and large UTF-8")
    }
}
