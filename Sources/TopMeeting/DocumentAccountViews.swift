import SwiftUI

struct DocumentAccountSettings: View {
    @EnvironmentObject var store: MeetingStore
    @InlineState private var service = ExternalDocumentService.google
    @InlineState private var values = [String:String]()
    @InlineState private var message = ""
    @InlineState private var waiting = false
    var fields: [(String,String,Bool)] {
        switch service {
        case .google: return [("clientId","Google 桌面应用 Client ID",false),("secret","Client Secret",true)]
        case .notion: return [("token","Notion 内部集成 Token",true),("parent","已与集成共享的父页面 ID",false)]
        case .ding: return [("clientId","钉钉应用 AppKey",false),("secret","AppSecret",true),("space","知识库空间 ID",false),("operator","操作人 Union ID",false),("parent","父节点 ID（选填）",false)]
        case .tencent: return [("token","腾讯文档个人 MCP Token",true)]
        }
    }
    var body: some View {
        Section(L10n.tr("其他会议文档")) {
            Picker(L10n.tr("文档平台"),selection:$service) {
                ForEach(ExternalDocumentService.allCases) { Text($0.name).tag($0) }
            }.disabled(waiting).onChange(of:service) { _,_ in values = [:]; message = "" }
            if let label = store.documentLabels[service.id] {
                Label(label,systemImage:"person.crop.circle.badge.checkmark")
                Toggle(L10n.tr("开始录音时创建会议文档"),isOn:Binding(get:{store.documentAutomatic[service.id] == true},set:{store.setDocumentAutomatic(service,$0)}))
                Button(L10n.tr("解除绑定")) {
                    do { try store.disconnectDocumentAccount(service); message = "" } catch { message = error.localizedDescription }
                }.disabled(waiting || store.recording)
            } else {
                if service == .tencent { Link(L10n.tr("获取腾讯文档个人授权"),destination:URL(string:"https://docs.qq.com/open/auth/mcp.html")!) }
                ForEach(fields,id:\.0) { key,label,secure in
                    let binding = Binding<String>(get:{values[key] ?? ""},set:{values[key] = $0})
                    if secure { SecureField(label,text:binding) } else { TextField(label,text:binding) }
                }
                Button(L10n.tr("绑定账号")) {
                    let chosen = service, settings = values
                    waiting = true; message = L10n.tr("正在等待授权")
                    Task { @MainActor in
                        defer { waiting = false }
                        do {
                            try await store.bindDocumentAccount(chosen,settings:settings)
                            store.setDocumentAutomatic(chosen,true); values = [:]; message = ""
                        } catch { message = error.localizedDescription }
                    }
                }.disabled(waiting || store.recording)
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct MeetingDocumentLinks: View {
    @EnvironmentObject var store: MeetingStore
    let meeting: Meeting
    @InlineState private var recovery = [String:String]()
    var body: some View {
        ForEach(ExternalDocumentService.allCases) { service in
            if let link = meeting.documentLinks?[service.id] {
                if let text = link.url, let url = service.verifiedURL(text) {
                    Link(destination:url) { Label(service.name,systemImage:"arrow.up.right.square") }
                } else if store.documentPending.contains(meeting.id.uuidString + service.id) {
                    Label(service.name+" · "+L10n.tr("正在建档"),systemImage:"clock")
                } else {
                    VStack(alignment:.leading) {
                        Text(service.name+" · "+(link.detail ?? L10n.tr("请核对云端建档结果"))).font(.caption)
                        HStack {
                            TextField(L10n.tr("已创建文档的链接"),text:Binding(get:{recovery[service.id] ?? ""},set:{recovery[service.id] = $0}))
                            Button(L10n.tr("关联")) { store.reconcileDocument(service,id:meeting.id,url:recovery[service.id]) }
                                .disabled(service.verifiedURL(recovery[service.id] ?? "") == nil)
                        }
                        Button(L10n.tr("已核对未创建，重试")) { store.reconcileDocument(service,id:meeting.id,url:nil) }
                    }
                }
            }
        }
    }
}
