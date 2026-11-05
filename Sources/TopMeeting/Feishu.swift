import Foundation

struct FeishuDocument: Codable {
    var id: String
    var url: String
    var content: String? = nil
    var board: String? = nil
    var attachments: [String] = []
    var pending: String? = nil
    var syncedAt: Date? = nil
    var pendingPayload: String? = nil
}
struct FeishuCLI {
    typealias Runner = @Sendable ([String],Data?) async throws -> Data
    var run: Runner
    init(executable: URL? = nil,boundAppID: String? = nil) {
        let url = executable ?? Self.executable
        run = { args,input in
            guard let url else { throw Gateway.error("飞书连接组件未安装，请重新构建客户端。") }
            return try await Task.detached(priority:.utility) {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                defer { try? FileManager.default.removeItem(at:directory) }
                let output = directory.appendingPathComponent("output.json"), errors = directory.appendingPathComponent("error.txt")
                FileManager.default.createFile(atPath:output.path,contents:nil,attributes:[.posixPermissions:0o600])
                FileManager.default.createFile(atPath:errors.path,contents:nil,attributes:[.posixPermissions:0o600])
                let stdout = try FileHandle(forWritingTo:output), stderr = try FileHandle(forWritingTo:errors)
                defer { try? stdout.close(); try? stderr.close() }
                let process = Process(); process.executableURL = url
                var stdin: FileHandle?
                defer { try? stdin?.close() }
                var arguments = args
                if let index = arguments.firstIndex(of:"--file"), index + 1 < arguments.count {
                    let file = URL(fileURLWithPath:arguments[index+1])
                    process.currentDirectoryURL = file.deletingLastPathComponent(); arguments[index+1] = file.lastPathComponent
                }
                if arguments.first != "profile" {
                    guard let id = boundAppID ?? UserDefaults.standard.string(forKey:"feishuBoundAppID"), Self.validAppID(id) else {
                        throw Gateway.error("请先绑定 TopMeeting 专用的飞书应用，再使用该应用登录。")
                    }
                    arguments = ["--profile","topmeeting-" + id] + arguments
                }
                process.arguments = arguments
                if let input {
                    let file = directory.appendingPathComponent("input.xml")
                    try input.write(to:file); try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
                    stdin = try FileHandle(forReadingFrom:file); process.standardInput = stdin
                }
                var environment = ProcessInfo.processInfo.environment
                environment["LARKSUITE_CLI_NO_UPDATE_NOTIFIER"] = "1"; environment["LARKSUITE_CLI_NO_SKILLS_NOTIFIER"] = "1"
                environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
                process.environment = environment; process.standardOutput = stdout; process.standardError = stderr
                try process.run()
                let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline:.now()+180,execute:timeout)
                process.waitUntilExit(); timeout.cancel()
                let data = try Data(contentsOf:output)
                guard process.terminationStatus == 0 else { throw Gateway.error("飞书操作未确认成功。请检查登录、文档/云盘权限及网络后再核对云端文档。") }
                return data
            }.value
        }
    }
    init(run: @escaping Runner) { self.run = run }
    static var executable: URL? {
        let paths: [String?] = [Bundle.main.resourceURL?.appendingPathComponent("Feishu/lark-cli").path,
                     FileManager.default.currentDirectoryPath + "/.feishu-runtime/node_modules/@larksuite/cli/bin/lark-cli",
                     "/opt/homebrew/bin/lark-cli", "/usr/local/bin/lark-cli"]
        return paths.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath:$0) }.map { URL(fileURLWithPath:$0) }
    }
    static func object(_ data: Data) throws -> [String:Any] {
        guard let object = try JSONSerialization.jsonObject(with:data) as? [String:Any], object["ok"] as? Bool != false, object["error"] == nil else { throw Gateway.error("飞书未返回可确认的操作结果。") }
        return object
    }
    static func receipt(_ data: Data) throws -> [String:Any] {
        let result = try object(data)
        guard result["ok"] as? Bool == true else { throw Gateway.error("飞书未返回成功回执，请核对云端。") }
        return result
    }
    static func validAppID(_ id: String) -> Bool {
        id.range(of:#"^cli_[a-zA-Z0-9]{4,64}$"#,options:.regularExpression) != nil
    }
    func bindApplication(id: String,secret: String) async throws {
        guard Self.validAppID(id), !secret.isEmpty else { throw Gateway.error("请填写有效的飞书 App ID 和 App Secret。") }
        _ = try await run(["profile","add","--name","topmeeting-" + id,"--app-id",id,"--brand","feishu","--app-secret-stdin"],Data((secret+"\n").utf8))
        UserDefaults.standard.set(id,forKey:"feishuBoundAppID")
    }
    func verifiedUser() async throws -> (ready: Bool,name: String?) {
        let object = try Self.object(await run(["auth","status","--json","--verify"],nil))
        let user = (object["identities"] as? [String:Any])?["user"] as? [String:Any]
        let ready = user?["available"] as? Bool == true && user?["status"] as? String == "ready" && object["verified"] as? Bool != false
        return (ready,ready ? user?["userName"] as? String : nil)
    }
    func status() async throws -> Bool {
        try await verifiedUser().ready
    }
    func login() async throws -> (URL,String) {
        let object = try Self.object(await run(["auth","login","--domain","docs","--domain","drive","--no-wait","--json"],nil))
        func find(_ value: Any) -> URL? {
            guard let dict = value as? [String:Any] else { return nil }
            for key in ["verification_uri_complete","verification_url","verification_uri"] {
                if let text = dict[key] as? String, let url = URL(string:text), url.scheme == "https" { return url }
            }
            for value in dict.values { if let url = find(value) { return url } }
            return nil
        }
        let nested = object["data"] as? [String:Any]
        guard let code = (object["device_code"] ?? nested?["device_code"]) as? String, let url = find(object) else { throw Gateway.error("请在终端完成飞书 CLI 应用配置后重试登录。") }
        return (url,code)
    }
    func finishLogin(code: String) async throws {
        _ = try Self.object(await run(["auth","login","--device-code",code,"--json"],nil))
    }
    func create(title: String) async throws -> FeishuDocument {
        let object = try Self.receipt(await run(["docs","+create","--as","user","--title",title,"--content","<p>TopMeeting 会议记录。后续内容以带时间的同步版本追加。</p>"],nil))
        let data = object["data"] as? [String:Any], doc = data?["document"] as? [String:Any]
        guard let id = doc?["document_id"] as? String, let url = doc?["url"] as? String, !id.isEmpty, Self.safeDocumentURL(url) != nil else { throw Gateway.error("飞书建档结果不完整，请先在飞书核对，避免重复建档。") }
        return FeishuDocument(id:id,url:url)
    }
    static func safeDocumentURL(_ text: String) -> URL? {
        guard let url = URL(string:text), url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host, ["feishu.cn","larksuite.com"].contains(where: { host == $0 || host.hasSuffix("."+$0) }), url.path.hasPrefix("/docx/") else { return nil }; return url
    }
    func append(document: String,xml: String) async throws {
        _ = try Self.receipt(await run(["docs","+update","--as","user","--doc",document,"--command","append","--content","-"],Data(xml.utf8)))
    }
    func attach(document: String,path: String) async throws {
        guard FileManager.default.fileExists(atPath:path) else { throw Gateway.error("原始录音文件不存在，未上传。") }
        _ = try Self.receipt(await run(["docs","+media-insert","--as","user","--doc",document,"--type","file","--file",path],nil))
    }
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;").replacingOccurrences(of:"'",with:"&apos;")
    }
    static func content(_ meeting: Meeting,final: Bool) -> String {
        let transcript = meeting.attributedLines.filter { $0.source.live != true }.map { "<p>[\(clock($0.time))] \(escape($0.speaker))\($0.overlap ? "（重叠发言，可能不完整）" : "")：\(escape($0.text))</p>" }.joined()
        let notes = NoteSection.parse(meeting.notes).map { section in
            "<h2>\(escape(section.title))</h2>" + section.body.components(separatedBy:"\n").filter { !$0.isEmpty }.map { "<p>\(escape($0))</p>" }.joined()
        }.joined()
        return "<h1>\(final ? "会后完整记录" : "会中记录")</h1>" + (notes.isEmpty ? "<p>结构化总结尚未生成，先保存实录。</p>" : notes) + "<h2>会议实录</h2>" + transcript
    }
    static func board(_ meeting: Meeting) -> String {
        let sections = NoteSection.parse(meeting.notes)
        guard !sections.isEmpty else { return "" }
        // A mind map expresses section membership only, without inventing causality or decisions.
        func label(_ text: String) -> String {
            text.replacingOccurrences(of:"\n",with:" ").replacingOccurrences(of:"\"",with:"＂").replacingOccurrences(of:"<",with:"〈").replacingOccurrences(of:">",with:"〉").replacingOccurrences(of:"&",with:"＆")
        }
        var mermaid = "mindmap\n  root[\"\(label(meeting.title))\"]\n"
        for (i,section) in sections.enumerated() {
            mermaid += "    s\(i)[\"\(label(section.title))\"]\n"
            for (j,line) in section.body.components(separatedBy:"\n").filter({ !$0.trimmingCharacters(in:.whitespaces).isEmpty }).prefix(8).enumerated() {
                mermaid += "      n\(i)_\(j)[\"\(label(String(line.prefix(100))))\"]\n"
            }
        }
        return "<h1>会议核心信息画板</h1><p>根据已生成纪要整理；长内容请以正文为准。</p><whiteboard type=\"mermaid\">\(escape(mermaid))</whiteboard>"
    }
}
