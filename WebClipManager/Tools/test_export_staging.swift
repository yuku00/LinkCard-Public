import Foundation
import Darwin

enum ClipError: Error { case invalid(String) }
enum ReadAccess { static func failure(_ operation: String, _ code: Int32) -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: ["operation": operation]) } }
@main struct Test {
 static func main() throws {
  let fm = FileManager.default
  // Exercise the same fixed Application Support path and namespace as the app.
  let a = try ExportStaging(), b = try ExportStaging()
  let source = Data("synthetic source - never changed".utf8)
  let one = try a.write(source, name: "one.txt")
  let two = try b.write(Data("other".utf8), name: "two.txt")
  let firstData = try Data(contentsOf: one); precondition(firstData == source)
  do { _ = try a.write(Data(), name: "one.txt"); fatalError("overwrite") } catch {}
  let afterCollision = try Data(contentsOf: one); precondition(afterCollision == source)
  do { _ = try a.write(Data(), name: "../escape"); fatalError("traversal") } catch {}
  do { _ = try a.write(source, name: "failure.txt", createFile: { _, _ in errno = EROFS; return -1 }); fatalError("EROFS") }
  catch { let e = error as NSError; precondition(e.domain == NSPOSIXErrorDomain && e.code == Int(EROFS) && e.userInfo["operation"] as? String == "createFile") }
  let victim = b.directory.appendingPathComponent("victim.txt")
  try Data("victim".utf8).write(to: victim)
  let link = a.directory.appendingPathComponent("evil")
  precondition(symlink(victim.path, link.path) == 0)
  do { _ = try a.write(Data("attack".utf8), name: "evil"); fatalError("symlink overwritten") } catch {}
  a.clear()
  let victimData = try Data(contentsOf: victim)
  precondition(fm.fileExists(atPath: two.path) && victimData == Data("victim".utf8))
  precondition(!fm.fileExists(atPath: one.path))
  // Unknown objects deliberately survive cleanup.
  precondition(fm.fileExists(atPath: link.path))
  _ = unlink(link.path); _ = rmdir(a.directory.path)
  _ = unlink(victim.path); b.clear()
  precondition(!fm.fileExists(atPath: two.path))
  // A symlink in the supplied parent is refused rather than followed.
  let testRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
  try fm.createDirectory(at: testRoot, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
  defer { try? fm.removeItem(at: testRoot) }
  let alias = testRoot.appendingPathComponent("alias")
  precondition(symlink(testRoot.path, alias.path) == 0)
  do { _ = try ExportStaging(parent: alias); fatalError("followed parent link") } catch {}
  print("PASS export: real support path, isolated sessions, EROFS, no overwrite, nofollow, cleanup and synthetic source")
 }
}
