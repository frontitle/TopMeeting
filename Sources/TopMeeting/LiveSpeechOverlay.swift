import SwiftUI
import AppKit
import Combine

struct LiveSpeechOverlay: View {
    let text: String
    let levels: [Double]
    let speaker: String
    let elapsed: Double
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            HStack(spacing:8) {
                Circle().fill(paused ? Color.orange : MeetingStyle.accent).frame(width:6,height:6)
                Text(L10n.tr(paused ? "已暂停" : "正在聆听")).font(.system(size:12,weight:.semibold))
                Spacer()
                Text(L10n.tr(paused ? "" : speaker)).font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth:200,alignment:.trailing)
            }
            Text(L10n.tr(text.isEmpty ? (paused ? "点击继续，接着记录会议" : "等待声音…") : String(text.suffix(42))))
                .font(.system(size:15,weight:.medium)).lineSpacing(3)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .frame(maxWidth:.infinity,alignment:.leading).lineLimit(2).frame(height:42,alignment:.topLeading)
            HStack(spacing:12) {
                Text(clock(elapsed)).font(.system(size:12,weight:.medium,design:.monospaced)).foregroundStyle(.secondary)
                HStack(alignment:.center,spacing:3) {
                    ForEach(Array(levels.enumerated()),id:\.offset) { _,level in
                        Capsule().fill(LinearGradient(colors:[MeetingStyle.accent,.cyan.opacity(0.7)],startPoint:.top,endPoint:.bottom))
                            .frame(width:3,height:paused ? 3 : 3+pow(max(0,min(1,(level+65)/50)),1.3)*19)
                    }
                }.frame(maxWidth:.infinity).frame(height:24)
                    .animation(reduceMotion ? nil : .easeOut(duration:0.16),value:levels)
                    .accessibilityLabel(L10n.tr(paused ? "收音已暂停" : "实时收音波形"))
                // Native button sits over this reserved area; it must receive hits.
                Color.clear.frame(width:32,height:28)
            }
        }.padding(12)
        .background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:16))
        .overlay(RoundedRectangle(cornerRadius:16).stroke(LinearGradient(colors:[MeetingStyle.accent.opacity(0.35),Color.cyan.opacity(0.12)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1))
    }
}

@MainActor final class ListeningPanelController: NSObject, ObservableObject {
    private var panel: NSPanel?
    private var subscriptions: Set<AnyCancellable> = []
    private weak var store: MeetingStore?
    private var pauseButton: NSButton?
    func connect(_ store: MeetingStore,showMain: @escaping () -> Void = {}) {
        guard panel == nil else { return }
        self.store = store
        let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:420,height:140),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.title = "TopMeeting 实时聆听"
        let host = DraggableListeningHost(rootView:ListeningPanelContent(store:store))
        host.showMain = showMain
        let button = NSButton(image:NSImage(systemSymbolName:"pause.fill",accessibilityDescription:"暂停录音")!,target:self,action:#selector(togglePause))
        button.bezelStyle = .circular; button.isBordered = true
        button.contentTintColor = .systemBlue
        button.translatesAutoresizingMaskIntoConstraints = true
        host.addSubview(button); host.control = button

        panel.contentView = host
        if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x:screen.visibleFrame.midX-210,y:screen.visibleFrame.minY+36)) }
        self.panel = panel; pauseButton = button
        store.$recording.removeDuplicates().sink { [weak self] active in
            if active { self?.panel?.orderFrontRegardless() } else { self?.panel?.orderOut(nil) }
        }.store(in:&subscriptions)
        store.$recordingPaused.combineLatest(store.$ending).sink { [weak self] paused,ending in
            let name = paused ? "继续录音" : "暂停录音"
            self?.pauseButton?.image = NSImage(systemSymbolName:paused ? "play.fill" : "pause.fill",accessibilityDescription:name)
            self?.pauseButton?.toolTip = name; self?.pauseButton?.setAccessibilityLabel(name)
            self?.pauseButton?.isEnabled = !ending
        }.store(in:&subscriptions)
    }
    @objc private func togglePause() { store?.toggleRecordingPause() }
}
private struct ListeningPanelContent: View {
    @ObservedObject var store: MeetingStore
    var body: some View {
        LiveSpeechOverlay(text:store.liveCaption,levels:store.inputLevels,speaker:store.listeningSpeaker,elapsed:store.elapsed,paused:store.recordingPaused)
            .padding(6).help(L10n.tr("双击打开会议；拖动调整位置"))
    }
}
private final class DraggableListeningHost<Content: View>: NSHostingView<Content> {
    weak var control: NSButton?
    var showMain: () -> Void = {}
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let control, control.bounds.contains(control.convert(point,from:self)) { return control }
        return bounds.contains(point) ? self : nil
    }
    override func layout() {
        super.layout()
        control?.frame = NSRect(x:bounds.width-50,y:isFlipped ? bounds.height-46 : 18,width:32,height:28)
    }
    override var acceptsFirstResponder: Bool { false }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 { showMain() } else { window?.performDrag(with:event) }
    }
}
