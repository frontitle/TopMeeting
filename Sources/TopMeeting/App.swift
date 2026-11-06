import SwiftUI
import UniformTypeIdentifiers
typealias ViewState<Value> = SwiftUI.State<Value>

private enum AppArtwork {
    static let icon = Bundle.main.url(forResource:"TopMeeting",withExtension:"icns")
        .flatMap { NSImage(contentsOf:$0) }
}

@main struct TopMeetingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationDidFinishLaunching(_ notification: Notification) {
            if let icon = AppArtwork.icon { NSApp.applicationIconImage = icon }
        }
    }
    @Environment(\.openWindow) private var openWindow
    @StateObject private var store = MeetingStore()
    @StateObject private var listeningPanel = ListeningPanelController()
    var body: some Scene {
        Window("TopMeeting", id:"main") {
            Workspace().environmentObject(store).environment(\.locale,Locale(identifier:store.interfaceLanguage)).frame(minWidth:1080, minHeight:720)
                .onAppear { listeningPanel.connect(store,showMain: {
                    openWindow(id:"main")
                    DispatchQueue.main.async {
                        if let main = NSApplication.shared.windows.first(where:{ $0.title == "TopMeeting" }) { main.deminiaturize(nil); main.makeKeyAndOrderFront(nil) }
                        NSApplication.shared.activate(ignoringOtherApps:true)
                    }
                }); NSApplication.shared.setActivationPolicy(.regular); NSApplication.shared.activate(ignoringOtherApps:true) }
        }.windowStyle(.automatic).windowToolbarStyle(.unified).defaultSize(width:1380, height:880)
        Settings { ConnectionSettings().environmentObject(store).environment(\.locale,Locale(identifier:store.interfaceLanguage)) }
    }
}
struct Workspace: View {
    @Environment(\.colorScheme) private var colorScheme
    private var sidebarText: Color { colorScheme == .dark ? Color(white:0.92) : Color(white:0.12) }
    private var sidebarDetail: Color { colorScheme == .dark ? Color(white:0.65) : Color(white:0.42) }
    @EnvironmentObject var store: MeetingStore
    @ViewState<Bool> private var paste = false
    @ViewState<Bool> private var voices = false
    @ViewState<VoiceProfile?> private var speakerToMark: VoiceProfile? = nil
    @ViewState<String> private var input = ""
    @ViewState<String> private var speaker = "说话人 1"
    @ViewState<String> private var context = ""
    @ViewState<Line?> private var editing: Line? = nil
    @ViewState<Bool> private var chatExpanded = true
    @ViewState<Bool> private var followTranscript = true
    @Environment(\.openSettings) private var openSettings
    @AppStorage("documentGuideDismissed") private var documentGuideDismissed = false
    private let accent = MeetingStyle.accent
    var body: some View {
        NavigationSplitView {
            VStack(alignment:.leading, spacing:18) {
                HStack(spacing:10) {
                    if let icon = AppArtwork.icon {
                        Image(nsImage:icon).renderingMode(.original).resizable()
                            .scaledToFit().frame(width:36,height:36).accessibilityHidden(true)
                    }
                    Text("TopMeeting").font(.system(size:19, weight:.semibold))

                }.padding(.top,20).padding(.horizontal,18)
                Button(action:store.create) { Label(L10n.tr("新建会议"), systemImage:"plus").font(.system(size:13,weight:.semibold)).frame(maxWidth:.infinity).padding(.vertical,9) }.buttonStyle(MeetingPrimaryButtonStyle()).padding(.horizontal,16).disabled(store.recording || store.starting || store.ending || store.replayingVoices)
                TextField(L10n.tr("搜索会议、纪要或说话人"),text:$store.search).textFieldStyle(.roundedBorder).padding(.horizontal,16)
                Button { store.showTrash(!store.showingTrash) } label: { Label(L10n.tr(store.showingTrash ? "返回会议资料库" : "最近删除"),systemImage:store.showingTrash ? "arrow.left" : "trash").frame(maxWidth:.infinity,alignment:.leading) }.buttonStyle(.plain).font(.caption).padding(.horizontal,20).disabled(store.recording || store.starting || store.ending || store.replayingVoices)
                if !store.showingTrash {
                    Picker(L10n.tr("会议状态"),selection:$store.meetingFilter) {
                        ForEach(MeetingFilter.allCases) { Text(L10n.tr($0.rawValue)).tag($0) }
                    }.labelsHidden().padding(.horizontal,16)
                }
                List {
                    if store.visibleMeetings.isEmpty { Text(L10n.tr("没有匹配的会议")).font(.caption).foregroundStyle(sidebarDetail) }
                    ForEach(store.meetingGroups) { group in
                    Section {
                        ForEach(group.meetings) { m in
                            Button { store.select(m.id); context = "" } label: {
                                HStack(alignment:.top, spacing:10) {
                                    Image(systemName:"text.bubble").font(.system(size:15)).foregroundStyle(store.selected == m.id ? accent : sidebarDetail).frame(width:30,height:34).background(store.selected == m.id ? accent.opacity(0.09) : Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:9))
                                    VStack(alignment:.leading, spacing:5) { Text(m.title).foregroundStyle(sidebarText).font(.system(size:13,weight:store.selected == m.id ? .semibold : .medium)).lineLimit(1); Text(m.date, format:.dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(sidebarDetail) }
                                    Spacer()
                                }.padding(.vertical,10).padding(.horizontal,8).background(store.selected == m.id ? accent.opacity(0.075) : .clear, in:RoundedRectangle(cornerRadius:12))
                            }.buttonStyle(.plain).disabled(store.recording || store.starting || store.ending || store.replayingVoices)
                            .contextMenu {
                                if m.deletedAt == nil { Button(L10n.tr("删除会议"),role:.destructive) { store.trash(m.id) }.disabled(store.recording || store.starting || store.ending || store.replayingVoices) }
                                else { Button(L10n.tr("恢复会议")) { store.restore(m.id) } }
                            }
                        }
                    } header: { Text(L10n.tr(group.id)).foregroundStyle(sidebarDetail) }
                    }
                }.listStyle(.sidebar)
                SettingsLink { Label(L10n.tr("设置"),systemImage:"gearshape").frame(maxWidth:.infinity,alignment:.leading) }
                    .buttonStyle(.plain).font(.system(size:13)).foregroundStyle(.secondary).padding(20)
            }.background(MeetingStyle.surface.opacity(0.55)).navigationSplitViewColumnWidth(min:220, ideal:245, max:290)
        } detail: {
            if let m = store.current {
                VStack(spacing:0) {
                    header(m)
                    Divider()
                    HSplitView {
                        VStack(spacing:0) {
                            transcript(m).frame(maxHeight:.infinity)
                            Divider()
                            conversation(m).frame(height:chatExpanded ? 220 : 52)
                        }.frame(minWidth:440)
                        intelligence(m).frame(minWidth:330)
                    }

                }.background(MeetingStyle.canvas)
            } else {
                VStack(spacing:22) {
                    Image(systemName:"waveform.badge.mic").font(.system(size:58,weight:.ultraLight)).foregroundStyle(accent).padding(30).background(accent.opacity(0.07), in:RoundedRectangle(cornerRadius:30))
                    Text(L10n.tr(store.showingTrash ? "最近删除中没有会议" : "开始第一场会议")).font(.system(size:26,weight:.semibold))
                    if !store.showingTrash { Text(L10n.tr("点击左侧「新建会议」开始。")).foregroundStyle(.secondary) }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }
        .onChange(of:store.selected) { _,_ in context = "" }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button { paste = true } label: { Label(L10n.tr("添加会议文字"),systemImage:"text.badge.plus") }
                    Button(action:store.export) { Label(L10n.tr("导出会议"),systemImage:"square.and.arrow.up") }.disabled(store.current == nil)
                    if let m = store.current {
                        Divider()
                        if m.deletedAt != nil { Button(L10n.tr("恢复会议")) { store.restore(m.id) } }
                        else { Button(L10n.tr("删除会议"),role:.destructive) { store.trash(m.id) }.disabled(store.recording || store.starting || store.ending || store.replayingVoices) }
                    }
                } label: { Label(L10n.tr("更多"),systemImage:"ellipsis.circle") }.help(L10n.tr("会议操作"))
            }
        }
        .sheet(isPresented:$voices) { SpeakerPeopleView().environmentObject(store) }
        .sheet(item:$speakerToMark) { speaker in SpeakerIdentityEditor(speaker:speaker).environmentObject(store) }
        .sheet(isPresented:$paste) {
            VStack(alignment:.leading, spacing:16) {
                Text(L10n.tr("添加会议文字")).font(.title2.bold())
                Text(L10n.tr("粘贴已有转写，或补充没有被录到的发言。")).foregroundStyle(.secondary)
                TextField(L10n.tr("说话人"), text:$speaker)
                TextEditor(text:$input).font(.body).frame(height:220).border(.quaternary)
                HStack { Button(L10n.tr("取消")) { paste = false }; Spacer(); Button(L10n.tr("添加")) { store.add(input, speaker:speaker); input = ""; paste = false }.buttonStyle(.borderedProminent).disabled(input.isEmpty) }
            }.padding(28).frame(width:580)
        }
        .sheet(item:$editing) { line in LineEditor(line:line) { text, name in store.correct(id:line.id,text:text,speaker:name) } }
        .disabled(!store.archiveAvailable)
        .alert("TopMeeting", isPresented:Binding(get:{store.notice != nil},set:{if !$0 { store.notice = nil }})) { Button(L10n.tr("好")) { store.notice = nil } } message: { Text(L10n.tr(store.notice ?? "")) }
    }
    func header(_ m: Meeting) -> some View {
        HStack(spacing:24) {
            VStack(alignment:.leading,spacing:12) {
                HStack(spacing:7) {
                    Text(L10n.tr("工作空间")); Image(systemName:"chevron.right").font(.system(size:8,weight:.semibold)); Text(L10n.tr("会议记录"))
                    if m.deletedAt != nil { MeetingBadge(title:"最近删除",symbol:"trash",tint:.orange) }
                }.font(.system(size:11)).foregroundStyle(.secondary)
                TextField(L10n.tr("会议主题"),text:Binding(get:{store.current?.title ?? ""},set:{ value in store.update { $0.title = value } }))
                    .font(.system(size:25,weight:.bold)).textFieldStyle(.plain)
                HStack(spacing:12) {
                    Text(m.date,format:.dateTime.month().day().hour().minute())
                    Label(L10n.tr("\(m.lines.filter { $0.live != true }.count) 段实录"),systemImage:"text.alignleft")
                    Button { voices = true } label: { Label(L10n.tr("\(store.meetingSpeakers.count) 位说话人"),systemImage:"person.2") }.buttonStyle(.plain).foregroundStyle(accent).help(L10n.tr("查看与管理本场说话人"))
                }.font(.system(size:11)).foregroundStyle(.secondary)
            }
            Spacer(minLength:0)
            VStack(alignment:.trailing,spacing:10) {
                HStack(spacing:10) {
                    if store.recording { MeetingBadge(title:store.ending ? "正在收尾" : (store.recordingPaused ? "已暂停" : "录音中"),symbol:"record.circle",tint:.red) }
                    else { MeetingBadge(title:"本机转写",symbol:"lock.shield",tint:.secondary) }
                    Text(clock(store.recording ? store.elapsed : m.duration)).monospacedDigit().font(.system(size:22,weight:.medium,design:.rounded))
                }
                HStack(spacing:8) {
                if store.recording {
                    Button(action:store.toggleRecordingPause) { Image(systemName:store.recordingPaused ? "play.fill" : "pause.fill") }
                        .buttonStyle(.bordered).help(L10n.tr(store.recordingPaused ? "继续录音" : "暂停录音")).disabled(store.ending)
                }
                Button(action:store.toggleRecording) {
                    HStack(spacing:8) {
                        if store.starting || store.ending { ProgressView().controlSize(.small) }
                        else { Image(systemName:store.recording ? "stop.fill" : "mic.fill") }
                        Text(L10n.tr(store.starting ? "准备录音…" : (store.ending ? "保存最后一句…" : (store.recording ? "结束并总结" : "开始录音"))))
                    }.font(.system(size:13,weight:.semibold)).padding(.horizontal,12).padding(.vertical,7)
                }.buttonStyle(MeetingPrimaryButtonStyle(tint:store.recording ? .red : MeetingStyle.brand))
                    .disabled(store.starting || store.ending || store.replayingVoices)
                }
            }
        }.padding(.horizontal,20).padding(.vertical,12).background(MeetingStyle.surface).disabled(m.deletedAt != nil)
    }
    func transcript(_ m: Meeting) -> some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:10) { Label(L10n.tr("会议实录"),systemImage:"text.alignleft").font(.system(size:15,weight:.semibold)); Spacer(); Toggle(L10n.tr("跟随实录"),isOn:$followTranscript).toggleStyle(.switch).controlSize(.mini).font(.caption).help(L10n.tr("选词纠错时会暂停跟随")) }.padding(.horizontal,24).padding(.top,22).padding(.bottom,8)
            Text(L10n.tr("完整记录每一段发言 · 选中词语即可纠正")).font(.system(size:11)).foregroundStyle(.secondary).padding(.horizontal,24).padding(.bottom,8)
            ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment:.leading,spacing:12) {
                    if m.lines.filter({ $0.live != true }).isEmpty {
                        ContentUnavailableView(L10n.tr("等待第一句发言"),systemImage:"waveform",description:Text(L10n.tr(store.recording ? "完整发言会自动进入实录。" : "点击开始录音，首次使用需允许麦克风和语音识别。")))
                    }
                    ForEach(m.transcriptParagraphs) { piece in
                        let line = piece.source
                        HStack(alignment:.top,spacing:12) {
                            Text(String(piece.speaker.prefix(1))).font(.system(size:12,weight:.semibold)).foregroundStyle(MeetingStyle.personColor(piece.speaker)).frame(width:32,height:32).background(MeetingStyle.personColor(piece.speaker).opacity(0.1),in:RoundedRectangle(cornerRadius:11))
                            VStack(alignment:.leading,spacing:8) {
                                HStack {
                                    if piece.speakerIDs.filter({$0 != "unknown"}).count == 1, let identity = piece.speakerIDs.first {
                                        SpeakerDropdown(speaker:VoiceProfile(id:identity,name:piece.speaker,seconds:0))
                                    } else if piece.speakerIDs.filter({$0 != "unknown"}).count > 1 {
                                        ForEach(piece.speakerIDs.filter({$0 != "unknown"}),id:\.self) { identity in
                                            SpeakerDropdown(speaker:VoiceProfile(id:identity,name:piece.speakerNames[identity] ?? m.voiceNames?[identity] ?? piece.speaker,seconds:0))
                                        }
                                    } else { SpeakerDropdown(speaker:VoiceProfile(id:"manual:"+line.id.uuidString,name:piece.speaker,seconds:0)) }
                                if line.live == true { Label(L10n.tr("正在识别"),systemImage:"circle.fill").font(.caption2).foregroundStyle(accent) }; Text(clock(piece.time)).font(.caption.monospacedDigit()).foregroundStyle(.secondary); Spacer(); Button { followTranscript = false; editing = line } label: { Image(systemName:"pencil") }.buttonStyle(.plain).help(L10n.tr("纠正文字或标记说话人")).disabled(line.live == true || m.deletedAt != nil) }
                                SelectableTranscript(text:piece.text,editable:line.live != true && m.deletedAt == nil,onInteraction: { followTranscript = false }) { selection,replacement,remember in
                                    let origin = piece.sourceRange?.location ?? 0
                                    try store.correctWord(lineID:line.id,expected:line.text,range:NSRange(location:origin+selection.location,length:selection.length),replacement:replacement,remember:remember)
                                }
                                if piece.overlap { Label(L10n.tr("多人重叠发言 · 转写可能不完整"),systemImage:"waveform.path.badge.plus").font(.caption2).foregroundStyle(.orange) }
                                if line.original != nil { Label(L10n.tr("已人工修订"),systemImage:"checkmark.circle").font(.caption2).foregroundStyle(.secondary) }
                            }
                        }.modifier(MeetingCard()).id(piece.id).contextMenu {
                            Button(L10n.tr("修改文字与说话人")) { followTranscript = false; editing = line }.disabled(line.live == true || m.deletedAt != nil)
                            Button(L10n.tr("删除这段发言"),role:.destructive) { store.deleteLine(line.id) }.disabled(line.live == true || m.deletedAt != nil)
                        }
                    }
                    Color.clear.frame(height:1).id("transcript-bottom")
                }.padding(.horizontal,20).padding(.vertical,12)
            }
            .onChange(of:m.lines.last(where: { $0.live != true })?.text) { _, _ in if followTranscript { scroll.scrollTo("transcript-bottom",anchor:.bottom) } }
            .onChange(of:m.lines.filter { $0.live != true }.count) { _, _ in if followTranscript { scroll.scrollTo("transcript-bottom",anchor:.bottom) } }
            }
            if !store.correctionStatus.isEmpty { Label(store.correctionStatus,systemImage:"checkmark.circle.fill").font(.caption2).foregroundStyle(.blue).padding(.horizontal,22).padding(.vertical,8) }
            if let path = m.audioPath { Button { NSWorkspace.shared.selectFile(path,inFileViewerRootedAtPath:"") } label: { Label(L10n.tr("查看原始录音"),systemImage:"waveform.path") }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).padding(.horizontal,20).padding(.bottom,12) }
        }
    }
    func conversation(_ m: Meeting) -> some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Button { chatExpanded.toggle() } label: {
                    HStack(spacing:8) { Image(systemName:"sparkles").foregroundStyle(accent); Text(L10n.tr("会议助手")).fontWeight(.semibold); Image(systemName:chatExpanded ? "chevron.down" : "chevron.up").font(.caption2) }
                }.buttonStyle(.plain)
                Spacer()
                if store.chatBusy { ProgressView().controlSize(.mini); Text(L10n.tr("正在回复")).font(.caption).foregroundStyle(.secondary) }
                else { Text(L10n.tr("提问 · 纠错 · 补充语境")).font(.caption).foregroundStyle(.secondary) }
            }.font(.system(size:13))
            if chatExpanded {
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment:.leading,spacing:14) {
                            if m.conversation.isEmpty {
                                Text(L10n.tr("补充会议背景、纠正理解，或问问刚才讨论了什么。")).font(.system(size:12)).foregroundStyle(.secondary)
                                if !m.context.isEmpty { Text(L10n.tr("此前补充：\(m.context)")).font(.caption).foregroundStyle(.secondary) }
                            }
                            ForEach(m.conversation) { message in
                                VStack(alignment:.leading,spacing:5) {
                                    Text(L10n.tr(message.role == "user" ? "你" : "会议 AI")).font(.caption2.weight(.semibold)).foregroundStyle(message.role == "user" ? .secondary : accent)
                                    Text(L10n.tr(.init(message.state == "pending" ? (store.chatStreaming.isEmpty ? "正在思考…" : store.chatStreaming) : message.text))).font(.system(size:13)).lineSpacing(4).textSelection(.enabled).foregroundStyle(message.state == "failed" ? .secondary : .primary)
                                    if message.state == "failed", message.id == m.conversation.last?.id {
                                        Button(L10n.tr("重试回复"),action:store.retryChat).buttonStyle(.borderless).font(.caption).disabled(store.chatBusy)
                                    }
                                }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
                                    .background(message.role == "user" ? accent.opacity(0.055) : Color.clear,in:RoundedRectangle(cornerRadius:10))
                            }
                            Color.clear.frame(height:1).id("chat-bottom")
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }.onChange(of:m.conversation.count) { _,_ in scroll.scrollTo("chat-bottom",anchor:.bottom) }
                    .onChange(of:store.chatStreaming) { _,_ in scroll.scrollTo("chat-bottom",anchor:.bottom) }
                }
                HStack(alignment:.bottom,spacing:10) {
                    TextField(L10n.tr("补充语境，或向会议助手提问…"),text:$context,axis:.vertical).lineLimit(1...3).textFieldStyle(.plain).onSubmit(sendMessage)
                    Button(action:sendMessage) { Image(systemName:"arrow.up").fontWeight(.semibold).frame(width:22,height:22) }.buttonStyle(.borderedProminent).tint(accent).disabled(context.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || store.chatBusy).help(L10n.tr("发送给会议 AI"))
                }.padding(11).background(.background,in:RoundedRectangle(cornerRadius:13)).overlay(RoundedRectangle(cornerRadius:13).strokeBorder(.quaternary))
            }
        }.padding(.horizontal,20).padding(.vertical,16).background(MeetingStyle.surface).disabled(m.deletedAt != nil)
    }
    func sendMessage() {
        let text = context.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty, !store.chatBusy else { return }
        if store.token.isEmpty || store.base.isEmpty { store.sendChat(text); return }
        store.sendChat(text); context = ""
    }
    func intelligence(_ m: Meeting) -> some View {
        let content = store.busy && !store.streaming.isEmpty ? store.streaming : m.notes
        return VStack(alignment:.leading,spacing:18) {
            HStack {
                Label(L10n.tr("结构化纪要"),systemImage:"sparkles").font(.headline)
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
            }
            HStack(spacing:7) {
                Circle().fill(store.recording ? .green : (m.summaryState == "complete" ? accent : .secondary)).frame(width:6,height:6)
                Text(L10n.tr(store.busy ? (store.recording ? "正在整理会议脉络" : "正在生成整场总结") : (store.recording ? "按需更新 · 会后自动总结" : (m.summaryState == "complete" ? "会后完整总结" : "会议纪要")))).font(.caption).foregroundStyle(.secondary)
            }
            if store.base.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || store.token.isEmpty || !store.connectionChecked {
                VStack(alignment:.leading,spacing:7) {
                    Label(L10n.tr(store.base.isEmpty || store.token.isEmpty ? "AI 纪要暂不可用" : "AI 连接尚未验证"),systemImage:"wifi.exclamationmark").font(.system(size:13,weight:.semibold))
                    Text(L10n.tr("在扩展中连接模型，即可生成纪要。"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(MeetingStyle.surface,in:RoundedRectangle(cornerRadius:12))
            } else if m.summaryState == "connection" || m.summaryState == "retry" {
                VStack(alignment:.leading,spacing:8) {
                    Label(L10n.tr(m.summaryState == "connection" ? "总结等待连接" : "总结尚未完成"),systemImage:"exclamationmark.circle").font(.system(size:13,weight:.medium))
                    Text(L10n.tr(m.summaryState == "connection" ? "录音已保存。配置 OpenClaw 后，即可生成整场总结。" : "上次完整纪要仍然保留，请重试生成最新总结。")).font(.caption).foregroundStyle(.secondary)
                    Text(L10n.tr("可从左下角设置检查连接，再使用下方按钮更新纪要。")).font(.caption).foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(accent.opacity(0.06),in:RoundedRectangle(cornerRadius:12))
            }
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    if content.isEmpty {
                        VStack(spacing:18) {
                            ZStack {
                                Circle().fill(LinearGradient(colors:[accent.opacity(0.08),accent.opacity(0.015)],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:132,height:132)
                                Image(systemName:"text.badge.checkmark").font(.system(size:46,weight:.ultraLight)).foregroundStyle(accent.opacity(0.55))
                                Image(systemName:"sparkle").font(.system(size:17)).foregroundStyle(accent.opacity(0.35)).offset(x:-66,y:-37)
                            }
                            Text(L10n.tr(store.busy ? "正在梳理整场讨论…" : "让每一次讨论，都有清晰的结论")).font(.system(size:19,weight:.medium))
                            Text(L10n.tr("点击更新，整理议题、决策与行动项。\n结束会议后，自动生成整场总结。")).font(.system(size:13)).foregroundStyle(.secondary).lineSpacing(6).multilineTextAlignment(.center)
                        }.frame(maxWidth:.infinity,minHeight:390)

                    } else {
                        ForEach(NoteSection.parse(content)) { section in
                            VStack(alignment:.leading,spacing:12) {
                                Label(section.title,systemImage:MeetingStyle.sectionSymbol(section.title)).font(.system(size:14,weight:.semibold)).foregroundStyle(accent)
                                Text(.init(section.body)).font(.system(size:14)).lineSpacing(7).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                            }.modifier(MeetingCard())
                        }
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            MeetingDocumentLinks(meeting:m)
            if m.feishu != nil || (store.documentPlatform == .feishu && (store.feishuReady || store.feishuAutoSync)) {
                FeishuMeetingPanel(meeting:m)
            } else if !store.recording && !store.ending && !documentGuideDismissed && m.audioPath != nil &&
                      store.documentLabels.isEmpty && m.documentLinks?.isEmpty != false {
                HStack {
                    VStack(alignment:.leading,spacing:3) {
                        Text(L10n.tr("会议文档")).font(.caption.bold())
                        Text(L10n.tr("连接账号，下次开会时自动建档。")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.tr("连接文档")) { store.settingsTab = "extensions"; openSettings() }
                    Button { documentGuideDismissed = true } label: { Image(systemName:"xmark") }
                        .buttonStyle(.plain).accessibilityLabel(L10n.tr("不再提示会议文档"))
                }.modifier(MeetingCard())
            }
            Divider()
            HStack {
                if (store.documentPlatform == .feishu && store.feishuReady) || m.feishu != nil { Label(L10n.tr("会后生成核心信息画板"),systemImage:"doc.richtext").font(.caption2).foregroundStyle(.tertiary) }
                Spacer()
                Button(L10n.tr(store.recording ? "更新纪要" : "生成完整总结")) { store.analyze() }.buttonStyle(.bordered).controlSize(.small).disabled(store.busy || m.lines.isEmpty || store.base.isEmpty || store.token.isEmpty)
            }
        }.padding(20).background(MeetingStyle.canvas).disabled(m.deletedAt != nil)
    }

}
struct LineEditor: View {
    @Environment(\.dismiss) var dismiss
    @ViewState<Line> var line: Line
    var save: (String,String) -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text(L10n.tr("纠正这段发言")).font(.title2.bold())
            TextField(L10n.tr("说话人姓名"),text:$line.speaker)
            TextEditor(text:$line.text).frame(height:180).border(.quaternary)
            Text(L10n.tr("原始识别内容会保留，后续纪要使用修订版本。仅修改本段说话人。")).font(.caption).foregroundStyle(.secondary)
            HStack { Button(L10n.tr("取消")) { dismiss() }; Spacer(); Button(L10n.tr("保存修订")) { save(line.text,line.speaker); dismiss() }.buttonStyle(.borderedProminent).disabled(line.text.isEmpty || line.speaker.isEmpty) }
        }.padding(28).frame(width:550)
    }
}
struct ConnectionSettings: View {
    @EnvironmentObject var store: MeetingStore
    var body: some View {
        TabView(selection:$store.settingsTab) {
            Form {
                Section(L10n.tr("语言")) {
                    Picker(L10n.tr("界面语言"),selection:$store.interfaceLanguage) { Text(L10n.tr("简体中文")).tag("zh-Hans"); Text("English").tag("en") }
                        .onChange(of:store.interfaceLanguage) { _,_ in store.saveLanguageSettings() }
                    Picker(L10n.tr("会议识别语言"),selection:$store.speechLocale) {
                        ForEach(Array(Set(store.speechLocales + [store.speechLocale])).sorted(),id:\.self) { code in
                            Text(Locale(identifier:store.interfaceLanguage).localizedString(forIdentifier:code) ?? code).tag(code)
                        }
                    }.disabled(store.recording || store.starting || store.ending)
                        .onChange(of:store.speechLocale) { _,_ in store.saveLanguageSettings() }
                    Picker(L10n.tr("纪要语言"),selection:$store.summaryLanguage) { Text(L10n.tr("简体中文")).tag("zh-Hans"); Text("English").tag("en") }
                        .disabled(store.recording || store.busy).onChange(of:store.summaryLanguage) { _,_ in store.saveLanguageSettings() }
                    Text(L10n.tr("识别语言在下次录音生效，首次使用可能下载本机模型。语言选择不改变原始发言。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            Section(L10n.tr("多人会议收音")) {
                Picker(L10n.tr("麦克风"),selection:$store.microphoneID) {
                    Text(L10n.tr("跟随系统默认输入")).tag(UInt32(0))
                    ForEach(store.microphones) { mic in Text(mic.name).tag(mic.id) }
                }.disabled(store.recording || store.starting || store.ending || store.replayingVoices)
                Button(L10n.tr("刷新麦克风列表")) { store.microphones = AudioDevices.inputs() }.disabled(store.recording || store.starting || store.ending || store.replayingVoices)
                HStack { Text(L10n.tr("识别增益")); Slider(value:$store.recognitionGain,in:1...6,step:0.5).disabled(store.recording || store.starting || store.ending || store.replayingVoices); Text(String(format:"%.1f×",store.recognitionGain)).monospacedDigit().frame(width:44) }
                Text(L10n.tr("基础增益默认 3×，轻声会自动补偿至最高 6×，近处声音按峰值限制增益。只增强送入识别器的声音，原始录音不变。录音开始前可调整。多人会议请使用能覆盖全场的麦克风，并在控制中心选择标准或宽谱，避免语音突显压低远处人声。")).font(.caption).foregroundStyle(.secondary)
            }
            if store.recording && !store.captureStatus.isEmpty { Text(store.captureStatus).font(.caption).foregroundStyle(.secondary) }
            }.formStyle(.grouped).tabItem { Label(L10n.tr("通用"),systemImage:"slider.horizontal.3") }.tag("general")
            ExtensionSettings().tabItem { Label(L10n.tr("扩展"),systemImage:"puzzlepiece.extension") }.tag("extensions")
        }.padding(18).frame(width:720,height:740)
    }
}

struct SpeakerPeopleView: View {
    @EnvironmentObject var store: MeetingStore
    @Environment(\.dismiss) private var dismiss
    @ViewState<VoiceProfile?> private var selected: VoiceProfile? = nil
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack { VStack(alignment:.leading,spacing:6) { Text(L10n.tr("会议说话人")).font(.title2.weight(.semibold)); Text(L10n.tr("自动发现声音，标记姓名后建立声纹")).font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Button(L10n.tr("完成")) { dismiss() } }
            Label(store.voiceStatus,systemImage:store.voiceReady ? "person.wave.2" : "hourglass").font(.caption).foregroundStyle(.secondary)
            Text(L10n.tr("不需要会前录音。参会者正常发言后会自动出现；同一人被拆成多个身份时，将其合并即可纠正本场记录并完善声纹。重叠与低质量片段不参与学习，身份不确定时保留未标记，不按识别窗口新增人员。")).font(.system(size:13)).foregroundStyle(.secondary).lineSpacing(5)
            HStack {
                if store.replayingVoices { ProgressView().controlSize(.small); Text(L10n.tr("正在回放分析已有录音…")).font(.caption) }
                else if store.current?.audioPath != nil { Button(L10n.tr("分析现有录音"),action:store.analyzeRecordedVoices).disabled(!store.voiceReady || store.recording || store.starting || store.identityBusy) }
                Spacer()
            }
            ScrollView {
                VStack(spacing:12) {
                    if store.meetingSpeakers.isEmpty { ContentUnavailableView(L10n.tr("等待会议中的声音"),systemImage:"person.wave.2",description:Text(L10n.tr("正常发言约几秒后，匿名说话人会自动出现在这里。"))) }
                    ForEach(store.meetingSpeakers) { speaker in
                        HStack(spacing:12) {
                            Image(systemName:"person.crop.circle.fill").font(.title2).foregroundStyle(.indigo)
                            VStack(alignment:.leading,spacing:4) { Text(speaker.name).fontWeight(.medium); Text(L10n.tr(speaker.id.hasPrefix("manual:") ? "文字标记 · 尚未关联声音" : String(format:"本场单人发言约 %.1f 秒",speaker.seconds))).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if speaker.id.hasPrefix("manual:") { SpeakerDropdown(speaker:speaker) }
                            else {
                                Button(L10n.tr("试听")) { store.auditionSpeaker(speaker.id) }.disabled(store.recording)
                                Button(L10n.tr("标记 / 合并")) { selected = speaker }.disabled(!store.voiceReady || store.identityBusy)
                            }
                        }.padding(14).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:12))
                    }
                }
            }
            if store.current?.lines.contains(where:{$0.words == nil}) == true {
                Text(L10n.tr("部分旧实录缺少词级时间戳：可分析录音、试听并标记人员，旧句子不会被强行归属。")).font(.caption).foregroundStyle(.secondary)
            }
            if store.current?.canUndoIdentity == true { Button(L10n.tr("撤销上次标记或合并"),action:store.undoSpeakerIdentity).disabled(store.identityBusy) }
            if !store.identityMessage.isEmpty { Text(store.identityMessage).font(.caption).foregroundStyle(.secondary) }
            Label(L10n.tr("仅在本机保存声纹与修订历史；低置信度保持匿名。"),systemImage:"lock.shield").font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width:660,height:590)
        .sheet(item:$selected) { SpeakerIdentityEditor(speaker:$0).environmentObject(store) }
    }
}
struct SpeakerIdentityEditor: View {
    @EnvironmentObject var store: MeetingStore
    @Environment(\.dismiss) private var dismiss
    let speaker: VoiceProfile
    @ViewState<String> private var name = ""
    @ViewState<String> private var target = ""
    @ViewState<Bool> private var submitted = false
    private var targets: [VoiceProfile] {
        var values = store.discoveredSpeakers.filter { $0.id != speaker.id }
        for profile in store.voiceProfiles where profile.id != speaker.id && !values.contains(where:{$0.id == profile.id}) { values.append(profile) }
        return values
    }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text(L10n.tr("标记或合并说话人")).font(.title2.weight(.semibold))
            Text(L10n.tr("当前：\(speaker.name)")).foregroundStyle(.secondary)
            Picker(L10n.tr("身份操作"),selection:$target) {
                Text(L10n.tr("填写姓名，建立或更新声纹")).tag("")
                ForEach(targets) { person in Text(L10n.tr("与 \(person.name) 合并")).tag(person.id) }
            }.disabled(store.identityBusy)
            if target.isEmpty { TextField(L10n.tr("姓名或称呼"),text:$name).textFieldStyle(.roundedBorder).disabled(store.identityBusy) }
            Text(L10n.tr("使用会议中已经采集的可靠单人样本学习，不需要重新录音。手工合并会保留不同收音条件下的样本；明显异常的样本会隔离，不会污染已有声纹。")).font(.system(size:13)).foregroundStyle(.secondary).lineSpacing(5)
            if store.identityBusy { ProgressView().controlSize(.small) }
            if submitted { Text(store.identityMessage).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button(L10n.tr("完成")) { dismiss() }.disabled(store.identityBusy)
                Spacer()
                Button(L10n.tr(target.isEmpty ? "保存姓名并学习" : "确认同一人并合并")) {
                    submitted = true; store.markSpeaker(source:speaker.id,name:name,target:target.isEmpty ? nil : target)
                }.buttonStyle(.borderedProminent).disabled(store.identityBusy || (target.isEmpty && name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty))
            }
        }.padding(28).frame(width:580)
        .onAppear { name = store.voiceProfiles.first(where:{$0.id == speaker.id})?.name ?? "" }
        .interactiveDismissDisabled(store.identityBusy)
    }
}
