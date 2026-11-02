import Foundation
struct Clip { let id: String; let title: String; let removalDisallowed: Bool }
enum ClipError: Error { case invalid(String) }
enum RecycleStore { static func backupTest(_ clip: Clip) throws {} }
func WCMExperimentalDelete(_ id: String) -> [AnyHashable: Any] { fatalError("test uses stub") }
@main struct Test {
 static func main() throws {
  let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory:true)
  try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:temp) }
  let settings = DeleteSettings(parent:temp)
  precondition(!settings.isEnabled)
  let clip = Clip(id:"ordinary.webclip",title:"普通书签",removalDisallowed:false)
  var backups=0, calls=0, on=false
  let backup: (Clip) throws -> Void = { _ in backups += 1 }
  let bridge: (String) -> [AnyHashable: Any] = { _ in calls += 1; return ["called":true,"returned":true,"source":"不存在"] }
  do { _ = try ExperimentalDelete.run(clip,firstConfirmed:true,secondConfirmed:true,backup:backup,bridge:bridge); fatalError("default enabled") } catch {}
  _ = try ExperimentalDelete.run(clip,firstConfirmed:false,secondConfirmed:true,backup:backup,enabled:{true},bridge:bridge)
  precondition(backups == 0 && calls == 0)
  do { _ = try ExperimentalDelete.run(clip,firstConfirmed:true,secondConfirmed:true,backup:{_ in throw ClipError.invalid("backup")},enabled:{true},bridge:bridge); fatalError("backup failure") } catch {}
  precondition(calls == 0)
  do { _ = try ExperimentalDelete.run(clip,firstConfirmed:true,secondConfirmed:true,backup:backup,enabled:{on},bridge:bridge); fatalError("disabled") } catch {}
  precondition(backups == 0 && calls == 0)
  on=true
  _ = try ExperimentalDelete.run(clip,firstConfirmed:true,secondConfirmed:true,backup:backup,enabled:{on},bridge:bridge)
  precondition(backups == 1 && calls == 1)
  do { _ = try ExperimentalDelete.run(clip,firstConfirmed:true,secondConfirmed:true,backup:{_ in on=false},enabled:{on},bridge:bridge); fatalError("disabled after backup") } catch {}
  precondition(calls == 1)
  let blocked=Clip(id:"x",title:"managed",removalDisallowed:true)
  do { _ = try ExperimentalDelete.run(blocked,firstConfirmed:true,secondConfirmed:true,backup:backup,enabled:{true},bridge:bridge); fatalError("managed") } catch {}
  precondition(calls == 1 && backups == 1)
  let results: [[AnyHashable:Any]] = [["called":true,"returned":true,"source":"不存在"], ["called":true,"returned":false,"source":"仍存在"], ["called":true,"returned":true,"source":"未知"], ["called":false]]
  precondition(results.map(ExperimentalDelete.succeeded) == [true,false,false,false])
  print("Swift synthetic default-off, cancellation, backup, ordinary title, switch recheck and managed checks passed")
 }
}
