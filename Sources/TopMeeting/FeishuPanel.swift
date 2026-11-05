import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

struct FeishuSettings: View {
    @EnvironmentObject var store: MeetingStore
    @InlineState private var appID = UserDefaults.standard.string(forKey:"feishuBoundAppID") ?? ""
    @InlineState private var secret = ""
    @InlineState private var confirmDisconnect = false
    var body: some View {
        Section(L10n.tr("飞书文档")) {
            TextField("飞书应用 App ID",text:$appID)
            SecureField("飞书应用 App Secret",text:$secret)
            Button("绑定专用应用") {
                let id = appID.trimmingCharacters(in:.whitespacesAndNewlines), value = secret
                secret = ""; store.feishuChecking = true
                Task { @MainActor in
                    defer { store.feishuChecking = false }
                    do { try await FeishuCLI().bindApplication(id:id,secret:value)
                        store.feishuLoginURL = nil; store.feishuDeviceCode = nil; store.feishuReady = false
                        if UserDefaults.standard.object(forKey:"feishuAutoSync") == nil { store.feishuAutoSync = true; store.saveFeishuPreferences() }
                        store.feishuStatus = "已绑定应用 "+id+"，请登录并核对飞书授权页中的应用名称和账号。"
                    } catch { store.feishuStatus = error.localizedDescription }
                }
            }.disabled(secret.isEmpty || !FeishuCLI.validAppID(appID) || store.feishuChecking)
            if let bound = UserDefaults.standard.string(forKey:"feishuBoundAppID") {
                HStack {
                    Text("已绑定应用 · "+bound).font(.caption)
                    Spacer()
                    Button(L10n.tr("解除绑定")) { confirmDisconnect = true }
                        .disabled(store.feishuChecking || store.recording || !store.feishuBusy.isEmpty)
                }
                .alert("解除此设备的飞书绑定？",isPresented:$confirmDisconnect) {
                    Button(L10n.tr("取消"),role:.cancel) {}
                    Button(L10n.tr("解除绑定"),role:.destructive) {
                        store.feishuChecking = true
                        Task { @MainActor in
                            defer { store.feishuChecking = false }
                            do { try await FeishuCLI().disconnectApplication()
                                store.feishuLoginURL = nil; store.feishuDeviceCode = nil; store.feishuReady = false
                                store.feishuAutoSync = false; store.saveFeishuPreferences(); store.feishuStatus = "已解除绑定"; appID = ""
                            } catch { store.feishuStatus = error.localizedDescription }
                        }
                    }
                }
            }
            Text(L10n.tr(store.feishuStatus)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L10n.tr("检查连接"),action:store.checkFeishu)
                Button(L10n.tr("登录飞书"),action:store.loginFeishu)
                if store.feishuChecking { ProgressView().controlSize(.small) }
            }.disabled(store.feishuChecking)
            if let url = store.feishuLoginURL {
                Link(L10n.tr("打开飞书授权页面"),destination:url)
                if let image = Self.qr(url.absoluteString) { Image(nsImage:image).interpolation(.none).resizable().frame(width:150,height:150).padding(10).background(.white).accessibilityLabel(L10n.tr("飞书授权二维码")) }
                Button(L10n.tr("我已授权，完成连接"),action:store.completeFeishuLogin).disabled(store.feishuChecking)
            }
            Toggle(L10n.tr("会中每分钟同步，会后自动归档"),isOn:$store.feishuAutoSync).onChange(of:store.feishuAutoSync) { _,_ in store.saveFeishuPreferences() }
            Toggle(L10n.tr("会后附上原始录音文件"),isOn:$store.feishuUploadAudio).onChange(of:store.feishuUploadAudio) { _,_ in store.saveFeishuPreferences() }
            Text(L10n.tr("同步实录和结构化纪要；完整总结生成后，再将核心信息绘成飞书画板。每次更新追加到本场文档，保留飞书中的人工编辑。仅使用用户身份，授权范围为文档和云盘；声纹保留本机。")).font(.caption).foregroundStyle(.secondary)
        }
    }
    static func qr(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(text.utf8)
        guard let output = filter.outputImage, let image = CIContext().createCGImage(output.transformed(by:CGAffineTransform(scaleX:6,y:6)),from:output.extent.applying(CGAffineTransform(scaleX:6,y:6))) else { return nil }
        return NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height))
    }
}
struct FeishuMeetingPanel: View {
    @EnvironmentObject var store: MeetingStore
    let meeting: Meeting
    @InlineState<Bool> private var confirmRetry = false
    @InlineState<String> private var recoveredURL = ""
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:10) {
                Label(L10n.tr("飞书会议文档"),systemImage:"doc.richtext").font(.caption.weight(.medium))
                Spacer()
                if let text = meeting.feishu?.url, let url = FeishuCLI.safeDocumentURL(text) { Link(L10n.tr("打开文档"),destination:url).font(.caption) }
                if store.feishuBusy.contains(meeting.id) { ProgressView().controlSize(.mini) }
                else { Button(L10n.tr("同步本场")) { store.syncFeishu() }.controlSize(.small).disabled(!store.feishuReady || meeting.feishu?.pending != nil || meeting.lines.isEmpty || store.ending) }
            }
            Text(L10n.tr(store.feishuStatus)).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            if let operation = meeting.feishu?.pending, !store.feishuBusy.contains(meeting.id) {
                Text(L10n.tr("待核对：\(operation)")).font(.caption).foregroundStyle(.orange)
                if meeting.feishu?.id.isEmpty == true {
                    TextField(L10n.tr("已创建文档的飞书链接"),text:$recoveredURL).textFieldStyle(.roundedBorder)
                    Button(L10n.tr("关联已创建的文档")) { store.recoverFeishuCreation(recoveredURL) }.disabled(FeishuCLI.safeDocumentURL(recoveredURL) == nil)
                } else { Button(L10n.tr("已在飞书完成，继续后续步骤")) { store.acceptFeishuPending() }.font(.caption) }
                Button(L10n.tr("核对后允许重试…")) { confirmRetry = true }.font(.caption)
            }
        }.padding(12).background(Color.blue.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
        .alert("确认上次操作未完成？",isPresented:$confirmRetry) {
            Button(L10n.tr("取消"),role:.cancel) {}
            Button(L10n.tr("我已核对，允许重试")) { store.allowFeishuRetry() }
        } message: { Text(L10n.tr("请先检查飞书云端。若已创建文档，请关联该文档；若内容、画板或录音已写入，请选择已完成，避免重复写入。")) }
    }
}
