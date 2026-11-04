import SwiftUI

@MainActor func makeQAStore() -> MeetingStore {
    let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/inline-ui-data")
    let store = MeetingStore(root:root)
    if store.meetings.isEmpty { store.create(); store.add("小爱讨论小爱。",speaker:"验收人员") }
    return store
}
@main struct InlineUIHarness: App {
    @StateObject private var store = makeQAStore()
    var body: some Scene {
        Window("TopMeeting · 原位交互验收",id:"qa") {
            VStack(alignment:.leading,spacing:24) {
                Text("原位交互验收 · 独立测试数据").font(.title2)
                if let m = store.current, let line = m.lines.first {
                    SpeakerDropdown(speaker:VoiceProfile(id:"manual:"+line.id.uuidString,name:line.speaker,seconds:0))
                    SelectableTranscript(text:line.text,editable:true) { range,replacement,remember in
                        try store.correctWord(lineID:line.id,expected:line.text,range:range,replacement:replacement,remember:remember)
                    }.frame(height:80)
                    Text("保存结果："+line.text).accessibilityIdentifier("saved-result")
                    Text(store.correctionStatus).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(32).frame(width:720,height:420).environmentObject(store)
                .onAppear { NSApplication.shared.setActivationPolicy(.regular); NSApplication.shared.activate(ignoringOtherApps:true) }
        }
    }
}
