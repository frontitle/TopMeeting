import Foundation

enum ExternalDocumentService: String, CaseIterable, Identifiable {
    case feishu, ding, tencent, google, notion
    var id: String { rawValue }
    var name: String {
        switch self {
        case .feishu: return "飞书文档"
        case .google: return "Google Docs"
        case .notion: return "Notion"
        case .ding: return "钉钉文档"
        case .tencent: return "腾讯文档"
        }
    }
    static func selected(in defaults: UserDefaults) -> Self? {
        if let saved = defaults.string(forKey:"meetingDocumentPlatform") { return Self(rawValue:saved) }
        let automatic = defaults.dictionary(forKey:"documentAutomatic") as? [String:Bool] ?? [:]
        let enabled = allCases.filter {
            $0 == .feishu ? defaults.bool(forKey:"feishuAutoSync") : automatic[$0.id] == true
        }
        return enabled.count == 1 ? enabled.first : nil
    }
    var credential: String { "doc-account-" + rawValue }
    func verifiedURL(_ value: String) -> URL? {
        let hosts: [String]
        switch self {
        case .feishu: return FeishuCLI.safeDocumentURL(value)
        case .google: hosts = ["docs.google.com"]
        case .notion: hosts = ["notion.so","notion.site"]
        case .ding: hosts = ["alidocs.com","dingtalk.com"]
        case .tencent: hosts = ["docs.qq.com"]
        }
        guard let url = URL(string:value), url.scheme == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, hosts.contains(where:{ host == $0 || host.hasSuffix("." + $0) }) else { return nil }
        return url
    }
}

enum DocumentBridge {
    struct Reply: Decodable {
        var account: [String:JSONValue]?
        var url: String?
        var error: String?
    }
    enum JSONValue: Codable {
        case string(String), number(Double)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let value = try? c.decode(String.self) { self = .string(value) }
            else { self = .number(try c.decode(Double.self)) }
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self { case .string(let value): try c.encode(value); case .number(let value): try c.encode(value) }
        }
    }
    static func run(_ request: Data) async throws -> Reply {
        try await Task.detached(priority:.utility) {
            guard let resources = Bundle.main.resourceURL else { throw Gateway.error("请使用打包的 TopMeeting 客户端绑定文档。") }
            let directory = resources.appendingPathComponent("DocumentsRuntime")
            let process = Process(), input = Pipe(), output = Pipe()
            process.executableURL = directory.appendingPathComponent("node")
            process.arguments = [directory.appendingPathComponent("macos-bridge.cjs").path]
            process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try process.run()
            try input.fileHandleForWriting.write(contentsOf:request); try input.fileHandleForWriting.close()
            let data = try output.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw Gateway.error("文档连接组件未完成，请检查应用配置。") }
            return try JSONDecoder().decode(Reply.self,from:data)
        }.value
    }
}

extension MeetingStore {
    func bindDocumentAccount(_ service: ExternalDocumentService,settings: [String:String]) async throws {
        let request = try JSONSerialization.data(withJSONObject:["action":"bind","provider":service.id,"settings":settings])
        let reply = try await DocumentBridge.run(request)
        if let error = reply.error { throw Gateway.error(error) }
        guard let account = reply.account, case let .string(label)? = account["label"] else { throw Gateway.error("未取得账号授权回执") }
        try Vault.save(String(decoding:try JSONEncoder().encode(account),as:UTF8.self),account:service.credential)
        documentLabels[service.id] = label
        UserDefaults.standard.set(documentLabels,forKey:"documentLabels")
    }
    func disconnectDocumentAccount(_ service: ExternalDocumentService) throws {
        try Vault.save("",account:service.credential)
        documentLabels.removeValue(forKey:service.id)
        UserDefaults.standard.set(documentLabels,forKey:"documentLabels")
        setDocumentAutomatic(service,false)
    }
    func setDocumentAutomatic(_ service: ExternalDocumentService,_ enabled: Bool) {
        documentAutomatic[service.id] = enabled
        UserDefaults.standard.set(documentAutomatic,forKey:"documentAutomatic")
    }
    private func saveDocumentLink(_ link: MeetingDocumentLink?,service: ExternalDocumentService,id: UUID) throws {
        guard let index = meetings.firstIndex(where:{$0.id==id && $0.deletedAt==nil}) else { throw Gateway.error("会议已移除") }
        let before = meetings[index].documentLinks
        var links = before ?? [:]; links[service.id] = link; meetings[index].documentLinks = links
        do { try archive.save(meetings) }
        catch { meetings[index].documentLinks = before; throw error }
    }
    func startDocumentLinks(id: UUID) {
        guard let service = documentPlatform, service != .feishu, documentAutomatic[service.id] == true else { return }
        Task { await createDocumentLink(service,id:id) }
    }
    func createDocumentLink(_ service: ExternalDocumentService,id: UUID) async {
        let key = id.uuidString + service.id
        guard !documentPending.contains(key), let m = meetings.first(where:{$0.id==id && $0.deletedAt==nil}),
              m.documentLinks?[service.id] == nil else { return }
        documentPending.insert(key); defer { documentPending.remove(key) }
        do {
            let bytes = Data(Vault.read(account:service.credential).utf8)
            guard !bytes.isEmpty else { throw Gateway.error("请重新绑定账号") }
            let account = try JSONSerialization.jsonObject(with:bytes)
            let request = try JSONSerialization.data(withJSONObject:["action":"create","provider":service.id,"account":account,"title":m.title])
            try saveDocumentLink(.init(status:"pending"),service:service,id:id)
            let reply = try await DocumentBridge.run(request)
            if let updated = reply.account { try Vault.save(String(decoding:try JSONEncoder().encode(updated),as:UTF8.self),account:service.credential) }
            if let error = reply.error { throw Gateway.error(error) }
            guard let url = reply.url, service.verifiedURL(url) != nil else { throw Gateway.error("云端未返回可用链接") }
            try saveDocumentLink(.init(status:"ready",url:url),service:service,id:id)
        } catch {
            do { try saveDocumentLink(.init(status:"uncertain",detail:error.localizedDescription),service:service,id:id) }
            catch { notice = error.localizedDescription }
        }
    }
    func reconcileDocument(_ service: ExternalDocumentService,id: UUID,url: String?) {
        guard !documentPending.contains(id.uuidString+service.id) else { return }
        do {
            if let text = url {
                guard service.verifiedURL(text) != nil else { throw Gateway.error("请填写此平台的 HTTPS 文档链接") }
                try saveDocumentLink(.init(status:"ready",url:text),service:service,id:id)
            } else {
                try saveDocumentLink(nil,service:service,id:id)
                Task { await createDocumentLink(service,id:id) }
            }
        } catch { notice = error.localizedDescription }
    }
}
