import AppKit
import SwiftUI
@main struct WorkspacePreview {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.applicationIconImage = NSImage(contentsOfFile:FileManager.default.currentDirectoryPath+"/apps/windows/src/logo.png")
        let dark = CommandLine.arguments.contains("dark")
        app.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
        let picker = CommandLine.arguments.contains("picker")
        let width: CGFloat = picker ? 1120 : (CommandLine.arguments.contains("compact") ? 1080 : 1380)
        let store = MeetingStore(root:FileManager.default.temporaryDirectory.appendingPathComponent("topmeeting-preview-"+UUID().uuidString))
        store.interfaceLanguage = ProcessInfo.processInfo.environment["TOPMEETING_UI_LANGUAGE"] ?? "zh-Hans"
        store.base = ""; store.token = ""; store.feishuAutoSync = false
        var meeting = Meeting(); meeting.title = "产品体验优化讨论 · 示例"; meeting.duration = 1842
        meeting.lines = [
            Line(time:12,speaker:"林悦",text:"今天我们先对齐会议助手的核心体验。实时字幕要清楚，完整发言进入实录后再修改，开会时尽量减少操作。"),
            Line(time:48,speaker:"陈晨",text:"我建议把说话人的标记做得更直接。第一次识别出说话人，点击就能填名字，之后同一个人的发言都同步显示姓名。"),
            Line(time:92,speaker:"林悦",text:"总结按需更新就可以，不要反复处理已经总结过的内容。结束会议后，再生成一份完整的纪要。"),
            Line(time:138,speaker:"周宁",text:"那我们今天先完成界面和交互的调整，明天用实际会议录音一起验收。负责人和时间都记到待办里。")]
        meeting.notes = "## 核心摘要\n围绕实时聆听、说话人标记与会后总结，优化多人会议的完整体验。\n\n## 已明确决策\n- 完整发言定稿后进入实录。[00:12]\n- 点击说话人即可直接修改姓名。[00:48]\n- 会中按需更新，结束后生成完整总结。[01:32]\n\n## 行动待办\n- 完成界面与交互调整。负责人：待确认；时间：今天。[02:18]\n- 使用实际录音验收。负责人：待确认；时间：明天。[02:18]"
        meeting.summaryState = "complete"
        var older = Meeting(); older.title = "项目进度同步 · 示例"; older.date = Date().addingTimeInterval(-86400)
        var last = Meeting(); last.title = "本周计划讨论 · 示例"; last.date = Date().addingTimeInterval(-172800)
        if CommandLine.arguments.contains("first-meeting") {
            meeting = Meeting(); meeting.title = "新会议"
        } else if CommandLine.arguments.contains("after-recording") {
            meeting.audioPath = "/preview/synthetic.caf"
            store.documentLabels = [:]; store.feishuReady = false
        }
        store.meetings = [meeting,older,last]; store.selected = meeting.id
        store.voiceReady = true; store.voiceStatus = "说话人识别已就绪"
        let root: AnyView
        if picker {
            root = AnyView(HStack(alignment:.top,spacing:20) {
                VStack(alignment:.leading,spacing:16) {
                    Text("输入前").font(.headline)
                    SpeakerPickerMenu(query:.constant(""),people:[],currentID:"guest",select:{ _ in },add:{ _ in })
                }
                VStack(alignment:.leading,spacing:16) {
                    Text("添加姓名").font(.headline)
                    SpeakerPickerMenu(query:.constant("张三"),people:[],currentID:"guest",select:{ _ in },add:{ _ in })
                }
                VStack(alignment:.leading,spacing:16) {
                    Text("匹配已有人员").font(.headline)
                    SpeakerPickerMenu(query:.constant("蔡"),people:[VoiceProfile(id:"cai",name:"蔡总",seconds:0)],currentID:"guest",select:{ _ in },add:{ _ in })
                }
            }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(MeetingStyle.surface))
        } else if CommandLine.arguments.contains("extensions") { root = AnyView(ExtensionSettings().environmentObject(store)) } else if CommandLine.arguments.contains("settings") { root = AnyView(ConnectionSettings().environmentObject(store)) } else { root = AnyView(Workspace().environmentObject(store)) }
        let host = NSHostingView(rootView:root.environment(\.colorScheme,dark ? .dark : .light))
        let window = NSPanel(contentRect:NSRect(x:0,y:0,width:width,height:picker ? 400 : 880),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.contentView = host; window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline:.now()+1.5) {
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) else { fatalError("No bitmap") }
            host.cacheDisplay(in:host.bounds,to:bitmap)
            let target = CommandLine.arguments[1]
            try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:target))
            print("Rendered",Int(host.bounds.width),Int(host.bounds.height),target)
            window.orderOut(nil); Darwin.exit(0)
        }
        app.run()
    }
}
