import SwiftUI
struct ExtensionSettings: View {
    @EnvironmentObject var store: MeetingStore
    var body: some View {
        Form {
            Section(L10n.tr("总结与会议助手")) {
                Picker(L10n.tr("模型扩展"),selection:Binding(get:{store.providerKind},set:store.selectProvider)) {
                    ForEach(SummaryProviderKind.allCases) { Text($0.title).tag($0) }
                }.disabled(store.busy || store.chatBusy || store.checking)
                TextField(L10n.tr("服务地址"),text:$store.base,prompt:Text("https://example.com/v1"))
                SecureField(L10n.tr(store.providerKind == .openClaw ? "Gateway 令牌" : "API Key"),text:$store.token)
                TextField(L10n.tr(store.providerKind == .openClaw ? "Agent 路由" : "模型名称"),text:$store.agent)
                Text(L10n.tr(store.providerKind == .openClaw ? "连接你已有的远程 OpenClaw，使用配置好的账户与模型。" : "支持提供 Chat Completions 与 SSE 的兼容服务。费用与额度由所选服务商决定，不共享 OpenClaw 的订阅额度。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L10n.tr("保存连接配置"),action:store.saveSettings)
                    Button(L10n.tr("测试连接"),action:store.probe).disabled(store.checking || store.base.isEmpty || store.token.isEmpty)
                    if store.checking { ProgressView().controlSize(.small) }
                }
                Text(L10n.tr("凭据分别存入钥匙串，不随会议导出。")).font(.caption).foregroundStyle(.secondary)
            }
            FeishuSettings()
            Section(L10n.tr("扩展能力")) {
                Text(L10n.tr("当前可用：OpenClaw、兼容模型 API、飞书文档。"))
                Text(L10n.tr("钉钉、Slack 和其他连接器将通过独立扩展接入，目前尚未实现。")).font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
