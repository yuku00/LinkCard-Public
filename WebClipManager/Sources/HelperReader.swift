import Foundation
import Darwin

enum HelperReader {
    struct Response: Decodable {
        let version: Int
        let errno: Int32
        let clips: [Clip]
        let skipped: Int
    }
    static func decode(_ data: Data) throws -> Scan {
        guard data.count <= 8 * 1024 * 1024 else { throw ClipError.invalid("辅助进程输出超限") }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.version == 1, (0...4096).contains(response.skipped), response.clips.count <= 1000 else {
            throw ClipError.invalid("辅助进程协议无效")
        }
        guard response.errno == 0 else { throw ReadAccess.failure("helperRead", response.errno) }
        var seen = Set<String>()
        for clip in response.clips {
            guard clip.id.hasSuffix(".webclip"), clip.id.utf8.count <= 255,
                  !clip.id.contains("/"), !clip.id.contains("\\"), !clip.id.contains("\0"),
                  seen.insert(clip.id).inserted, clip.title.count <= 8192,
                  clip.url.count <= 65536, (clip.icon?.count ?? 0) <= 256 * 1024 else {
                throw ClipError.invalid("辅助进程条目无效")
            }
        }
        var scan = Scan()
        scan.clips = response.clips.sorted { $0.id < $1.id }
        if response.skipped > 0 { scan.issues = [ItemResult(id: "helper-skipped", message: "\(response.skipped) 项格式或只读校验未通过；未读取这些项目")] }
        return scan
    }
    // Called only from Repository actor following the scan button; never the UI thread.
    static func scan() throws -> Scan {
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: "WebClipReadHelper") else {
            throw ClipError.invalid("未找到已签名只读辅助进程")
        }
        var output: UnsafeMutablePointer<UInt8>?
        var length = 0
        var status: Int32 = 0
        let error = wcm_helper_run(executable.path, "webclip-list", 8000, &output, &length, &status)
        StartupLog.helper(error: error, status: status)
        guard error == 0, let output else { throw ClipError.invalid("辅助进程失败 errno=\(error)，exit/signal=\(status)") }
        defer { free(output) }
        do { return try decode(Data(bytes: output, count: length)) }
        catch let error as NSError where error.domain == NSPOSIXErrorDomain { throw error }
        catch { throw ClipError.invalid("辅助进程响应校验失败（不记录数据内容）") }
    }
}
