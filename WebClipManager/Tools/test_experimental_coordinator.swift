import Foundation
struct Clip { let id: String; let title: String; let removalDisallowed: Bool }
enum ClipError: Error { case invalid(String) }
enum RecycleStore { static func backupTest(_ clip: Clip) throws {} }
func WCMExperimentalDelete(_ id: String) -> [AnyHashable: Any] { fatalError("test uses stub") }
@main struct Test {
    static func main() throws {
        let clip = Clip(id:"A.webclip",title:"WCM-DELETE-TEST",removalDisallowed:false)
        var backups=0, calls=0
        let backup: (Clip) throws -> Void = { _ in backups += 1 }
        let bridge: (String) -> [AnyHashable: Any] = { _ in calls += 1; return ["called":true,"returned":true] }
        _ = try ExperimentalDelete.run(clip,firstConfirmed:false,secondConfirmed:true,backup:backup,bridge:bridge)
        _ = try ExperimentalDelete.run(clip,firstConfirmed:true,secondConfirmed:false,backup:backup,bridge:bridge)
        precondition(backups == 0 && calls == 0)
        do { _ = try ExperimentalDelete.run(clip,firstConfirmed:true,secondConfirmed:true,backup:{ _ in throw ClipError.invalid("backup") },bridge:bridge); fatalError("backup failure not thrown") } catch {}
        precondition(calls == 0)
        _ = try ExperimentalDelete.run(clip,firstConfirmed:true,secondConfirmed:true,backup:backup,bridge:bridge)
        precondition(backups == 1 && calls == 1)
        print("Swift synthetic confirmation and backup checks passed")
    }
}
