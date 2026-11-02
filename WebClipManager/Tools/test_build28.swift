import Foundation
import Darwin

enum ClipError: Error { case invalid(String) }
enum ReadAccess { static func failure(_ operation: String, _ code: Int32) -> Error { ClipError.invalid("\(operation): \(code)") } }

@main struct Test {
 static func main() throws {
  let fm = FileManager.default
  let root = fm.temporaryDirectory.appendingPathComponent("wcm28-" + UUID().uuidString, isDirectory: true)
  try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  defer { try? fm.removeItem(at: root) }
  let notes = NotesAutoReadSettings(parent: root), deletes = DeleteSettings(parent: root)
  precondition(!notes.isEnabled && !deletes.isEnabled)
  try notes.setEnabled(true)
  precondition(NotesAutoReadSettings(parent: root).isEnabled && !deletes.isEnabled)
  try deletes.setEnabled(true)
  try notes.setEnabled(false)
  precondition(!notes.isEnabled && deletes.isEnabled)
  try notes.setEnabled(true)
  let file = root.appendingPathComponent("org.example.WebClipManager.notes-auto-read-settings/settings.dat")
  try Data("corrupt\n".utf8).write(to: file)
  precondition(!notes.isEnabled && deletes.isEnabled)
  try notes.setEnabled(true)
  try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
  precondition(!notes.isEnabled)
  do { try notes.setEnabled(false); fatalError("unsafe existing file accepted") } catch {}
  var p = NotesAutoReadPolicy()
  precondition(!p.beginIfAllowed(enabled: false, busy: false, hasSelection: false, readState: "notRead"))
  precondition(!p.beginIfAllowed(enabled: true, busy: true, hasSelection: false, readState: "notRead"))
  precondition(!p.beginIfAllowed(enabled: true, busy: false, hasSelection: true, readState: "notRead"))
  precondition(!p.beginIfAllowed(enabled: true, busy: false, hasSelection: false, readState: "failed"))
  precondition(p.beginIfAllowed(enabled: true, busy: false, hasSelection: false, readState: "notRead"))
  precondition(!p.beginIfAllowed(enabled: true, busy: false, hasSelection: false, readState: "notRead"))
  var s: Set<String> = ["hidden"]
  SelectionPolicy.selectVisible(["a", "b"], selected: &s)
  precondition(s == ["hidden", "a", "b"])
  SelectionPolicy.toggle("a", selected: &s)
  precondition(s == ["hidden", "b"])
  SelectionPolicy.afterRead(success: false, selected: &s)
  precondition(s == ["hidden", "b"])
  SelectionPolicy.afterRead(success: true, selected: &s)
  precondition(s.isEmpty)
  SelectionPolicy.selectVisible(["a", "b"], selected: &s)
  SelectionPolicy.clear(&s)
  precondition(s.isEmpty)
  print("PASS build28 synthetic storage, once/busy/selection, read and clear")
 }
}
