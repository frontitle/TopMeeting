import Foundation

extension MeetingStore {
    func refreshFeishuIdentity() async throws {
        var name: String?
        if let cli = feishuClient as? FeishuCLI {
            let user = try await cli.verifiedUser()
            feishuReady = user.ready; name = user.name
        } else { feishuReady = try await feishuClient.status() }
        feishuStatus = feishuReady ? "飞书用户已连接" + (name.map { " · " + $0 } ?? "") : "请登录已绑定的飞书应用"
    }
    func checkFeishu() {
        guard !feishuChecking else { return }; feishuChecking = true
        Task {
            defer { feishuChecking = false }
            do { try await refreshFeishuIdentity() }
            catch { feishuReady = false; feishuStatus = error.localizedDescription }
        }
    }
    func loginFeishu() {
        guard !feishuChecking else { return }; feishuChecking = true
        Task {
            defer { feishuChecking = false }
            do { let (url,code) = try await feishuClient.login(); feishuLoginURL = url; feishuDeviceCode = code; feishuStatus = "请打开授权链接，完成后点击“我已授权”" }
            catch { feishuStatus = error.localizedDescription }
        }
    }
    func completeFeishuLogin() {
        guard let code = feishuDeviceCode, !feishuChecking else { return }; feishuChecking = true
        Task {
            defer { feishuChecking = false; feishuDeviceCode = nil; feishuLoginURL = nil }
            do { try await feishuClient.finishLogin(code:code); try await refreshFeishuIdentity() }
            catch { feishuReady = false; feishuStatus = error.localizedDescription }
        }
    }
    func saveFeishuPreferences() {
        UserDefaults.standard.set(feishuAutoSync,forKey:"feishuAutoSync")
        UserDefaults.standard.set(feishuUploadAudio,forKey:"feishuUploadAudio")
    }
    func syncFeishu(id: UUID? = nil,final: Bool? = nil) {
        guard let id = id ?? selected else { return }
        let isFinal = final ?? (!recording && !ending)
        Task { await performFeishuSync(id:id,final:isFinal) }
    }
    func setFeishu(_ state: FeishuDocument,id: UUID) throws {
        guard let i = meetings.firstIndex(where: { $0.id == id }) else { return }
        let previous = meetings[i].feishu
        meetings[i].feishu = state
        do { try JSONEncoder().encode(meetings).write(to:directory.appendingPathComponent("meetings.json"),options:.atomic) }
        catch { meetings[i].feishu = previous; throw Gateway.error("无法保存同步进度，本次同步已暂停。") }
    }
    func performFeishuSync(id: UUID,final: Bool) async {
        guard !feishuBusy.contains(id), let meeting = meetings.first(where: { $0.id == id }), meeting.deletedAt == nil else { return }
        guard feishuReady else { feishuStatus = "请先在连接设置中登录飞书"; return }
        guard meeting.feishu?.pending == nil else { feishuStatus = "上次写入结果待核对，请先打开飞书文档检查"; return }
        feishuBusy.insert(id); defer { feishuBusy.remove(id) }
        let client = feishuClient
        var state = meeting.feishu ?? FeishuDocument(id:"",url:"")
        func persist() throws { try setFeishu(state,id:id) }
        func stillActive() throws {
            guard meetings.contains(where: { $0.id == id && $0.deletedAt == nil }) else { throw Gateway.error("会议已移入最近删除，后续同步已停止。") }
        }
        do {
            if state.id.isEmpty {
                state.pending = "创建会议文档"; try persist()
                state = try await client.create(title:meeting.title)
                try persist()
            }
            try stillActive()
            guard final || meeting.lines.contains(where:{ $0.live != true }) else {
                feishuStatus = "会议文档已创建"; return
            }
            let content = FeishuCLI.content(meeting,final:final)
            if state.content != content {
                state.pending = "追加会议记录"; state.pendingPayload = content; try persist()
                try await client.append(document:state.id,xml:content)
                state.content = content; state.pending = nil; state.pendingPayload = nil; try persist()
            }
            // Final board is generated only from a complete summary, never from placeholders.
            if final, meeting.summaryState == "complete" {
                try stillActive()
                let board = FeishuCLI.board(meeting)
                if !board.isEmpty, state.board != board {
                    state.pending = "写入会后画板"; state.pendingPayload = board; try persist()
                    try await client.append(document:state.id,xml:board)
                    state.board = board; state.pending = nil; state.pendingPayload = nil; try persist()
                }
            }
            if final, feishuUploadAudio, !(recording && selected == id) {
                for path in meeting.audioSegments ?? meeting.audioPath.map({ [$0] }) ?? [] where !state.attachments.contains(path) {
                    try stillActive(); state.pending = "上传录音：" + URL(fileURLWithPath:path).lastPathComponent; state.pendingPayload = path; try persist()
                    try await client.attach(document:state.id,path:path)
                    state.attachments.append(path); state.pending = nil; state.pendingPayload = nil; try persist()
                }
            }
            state.syncedAt = Date(); try persist()
            feishuStatus = final ? "会后记录已同步；画板以完整总结为准" : "会中实录已同步到飞书"
        } catch {
            // Do not guess whether a non-idempotent write reached the service.
            feishuStatus = "同步暂停：\(error.localizedDescription)\(state.pending == nil ? "" : " 请核对云端后再决定重试。")"
        }
    }
    func recoverFeishuCreation(_ text: String) {
        guard let url = FeishuCLI.safeDocumentURL(text), let id = selected, !feishuBusy.contains(id), var state = current?.feishu, state.id.isEmpty else { return }
        state.id = String(url.path.dropFirst(6)); state.url = url.absoluteString; state.pending = nil
        do { try setFeishu(state,id:id); feishuStatus = "已关联云端文档，可继续同步。" } catch { feishuStatus = error.localizedDescription }
    }
    func acceptFeishuPending() {
        guard let id = selected, !feishuBusy.contains(id), var state = current?.feishu, let pending = state.pending, let payload = state.pendingPayload else { return }
        if pending == "追加会议记录" { state.content = payload }
        else if pending == "写入会后画板" { state.board = payload }
        else if pending.hasPrefix("上传录音：") { if !state.attachments.contains(payload) { state.attachments.append(payload) } }
        else { return }
        state.pending = nil; state.pendingPayload = nil
        do { try setFeishu(state,id:id); feishuStatus = "已确认上一步完成，可继续同步。" } catch { feishuStatus = error.localizedDescription }
    }
    func allowFeishuRetry() {
        guard let id = selected, let i = meetings.firstIndex(where: { $0.id == id }), !feishuBusy.contains(id) else { return }
        meetings[i].feishu?.pending = nil; meetings[i].feishu?.pendingPayload = nil; save(); feishuStatus = "已允许重试；请确认上次操作未在飞书完成。"
    }
}
