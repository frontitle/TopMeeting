import SwiftUI
import AppKit

typealias InlineState<Value> = SwiftUI.State<Value>
typealias InlineFocus<Value: Hashable> = SwiftUI.FocusState<Value>

struct SelectableTranscript: NSViewRepresentable {
    var text: String
    var editable: Bool
    var onInteraction: () -> Void = {}
    var save: (NSRange,String,Bool) throws -> Void
    func makeNSView(context: Context) -> CorrectionTextView {
        let view = CorrectionTextView()
        view.delegate = view
        view.isEditable = false; view.isSelectable = true; view.drawsBackground = false
        view.isRichText = false; view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isHorizontallyResizable = false; view.isVerticallyResizable = true
        view.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        return view
    }
    func updateNSView(_ view: CorrectionTextView, context: Context) {
        view.canCorrect = editable; view.saveCorrection = save; view.onInteraction = onInteraction
        if view.string != text {
            view.correctionPopover?.close()
            let style = NSMutableParagraphStyle(); style.lineSpacing = 7
            view.textStorage?.setAttributedString(NSAttributedString(string:text,attributes:[.font:NSFont.systemFont(ofSize:15),.foregroundColor:NSColor.labelColor,.paragraphStyle:style]))
            view.invalidateIntrinsicContentSize()
        }
    }
    static func dismantleNSView(_ view: CorrectionTextView, coordinator: ()) {
        view.cancelCorrection()
        view.delegate = nil
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CorrectionTextView, context: Context) -> CGSize? {
        let width = max(1,proposal.width ?? 500)
        nsView.textContainer?.containerSize = CGSize(width:width,height:CGFloat.greatestFiniteMagnitude)
        if let container = nsView.textContainer { nsView.layoutManager?.ensureLayout(for:container) }
        let height = nsView.textContainer.flatMap { nsView.layoutManager?.usedRect(for:$0).height } ?? 24
        return CGSize(width:width,height:ceil(height)+2)
    }
}
final class CorrectionTextView: NSTextView, NSTextViewDelegate {
    var onInteraction: (() -> Void)?
    func cancelCorrection() {
        selectionWork?.cancel(); selectionWork = nil
        correctionPopover?.close(); correctionPopover = nil
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { cancelCorrection() }
        super.viewWillMove(toWindow:newWindow)
    }
    override func mouseDown(with event: NSEvent) {
        if canCorrect { onInteraction?() }
        super.mouseDown(with:event)
    }
    var canCorrect = false
    var saveCorrection: ((NSRange,String,Bool) throws -> Void)?
    var correctionPopover: NSPopover?
    private var selectionWork: DispatchWorkItem?
    private var lastPresented = NSRange(location:NSNotFound,length:0)
    func textViewDidChangeSelection(_ notification: Notification) {
        selectionWork?.cancel()
        let range = selectedRange()
        if range.length == 0 { lastPresented = NSRange(location:NSNotFound,length:0); return }
        guard canCorrect, window != nil, !NSEqualRanges(range,lastPresented) else { return }
        onInteraction?()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.canCorrect, NSEqualRanges(self.selectedRange(),range) else { return }
            if NSEvent.pressedMouseButtons != 0 { self.textViewDidChangeSelection(notification); return }
            self.showCorrection(nil)
        }
        selectionWork = work
        DispatchQueue.main.asyncAfter(deadline:.now()+0.18,execute:work)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for:event) ?? NSMenu()
        let item = NSMenuItem(title:canCorrect ? "纠正所选词语…" : "本句收句后可纠正",action:#selector(showCorrection(_:)),keyEquivalent:"")
        item.target = self; item.isEnabled = canCorrect && selectedRange().length > 0
        menu.insertItem(NSMenuItem.separator(),at:0); menu.insertItem(item,at:0)
        return menu
    }
    @objc func showCorrection(_ sender: Any?) {
        let range = selectedRange()
        guard canCorrect, let hostWindow = window, hostWindow.isVisible, !isHiddenOrHasHiddenAncestor, range.length > 0, NSMaxRange(range) <= (string as NSString).length else { return }
        lastPresented = range
        let selected = (string as NSString).substring(with:range)
        guard selected.count <= 120 else { return }
        let snapshot = string
        let popover = NSPopover(); popover.behavior = .semitransient
        popover.contentViewController = NSHostingController(rootView:WordCorrectionPopover(selected:selected) { [weak self,weak popover] replacement,remember in
            guard let self, self.string == snapshot else { throw Gateway.error("原文已更新，请重新选择。") }
            try self.saveCorrection?(range,replacement,remember)
            popover?.close()
        })
        correctionPopover?.close(); correctionPopover = popover
        let glyphs = layoutManager?.glyphRange(forCharacterRange:range,actualCharacterRange:nil) ?? NSRange(location:0,length:0)
        var rect = textContainer.flatMap { layoutManager?.boundingRect(forGlyphRange:glyphs,in:$0) } ?? bounds
        rect.origin.x += textContainerOrigin.x; rect.origin.y += textContainerOrigin.y
        guard window === hostWindow, hostWindow.isVisible, !visibleRect.isEmpty,
              rect.intersects(visibleRect), rect.width.isFinite, rect.height.isFinite else {
            correctionPopover = nil; return
        }
        popover.show(relativeTo:rect.intersection(visibleRect),of:self,preferredEdge:.maxY)
    }
}
struct WordCorrectionPopover: View {
    let selected: String
    let save: (String,Bool) throws -> Void
    @InlineState<String> private var replacement = ""
    @InlineState<Bool> private var remember = true
    @InlineState<String> private var error = ""
    @InlineFocus<Bool> private var focused: Bool
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Label(L10n.tr("纠正词语"),systemImage:"pencil.line").font(.system(size:14,weight:.semibold))
            Text(L10n.tr("原文：\(selected)")).font(.system(size:12)).foregroundStyle(.secondary).lineLimit(2)
            TextField(L10n.tr("正确写法"),text:$replacement).textFieldStyle(.roundedBorder).focused($focused).onSubmit(commit)
            Toggle(L10n.tr("加入常用术语，用于后续会议"),isOn:$remember).font(.system(size:12)).toggleStyle(.checkbox)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Text(L10n.tr("保留原始识别记录")).font(.caption2).foregroundStyle(.tertiary); Spacer(); Button(L10n.tr(remember ? "纠正并记住" : "保存纠正"),action:commit).buttonStyle(.borderedProminent).tint(.blue).disabled(replacement.isEmpty || replacement == selected).keyboardShortcut(.defaultAction) }
        }.padding(18).frame(width:340)
        .onAppear { replacement = selected; focused = true }
    }
    func commit() { do { try save(replacement,remember) } catch { self.error = error.localizedDescription } }
}

struct SpeakerDropdown: View {
    @EnvironmentObject var store: MeetingStore
    let speaker: VoiceProfile
    @InlineState<Bool> private var open = false
    @InlineState<String> private var query = ""
    @InlineState<Bool> private var submitted = false
    private var canChange: Bool { !store.identityBusy && (store.voiceReady || speaker.id.hasPrefix("manual:")) }
    var body: some View {
        Button { query = ""; submitted = false; open.toggle() } label: {
            HStack(spacing:5) {
                Text(speaker.name).font(.system(size:12,weight:.semibold))
                Image(systemName:open ? "chevron.up" : "chevron.down").font(.system(size:9,weight:.semibold))
            }.foregroundStyle(MeetingStyle.accent).padding(.horizontal,10).padding(.vertical,6)
                .background(MeetingStyle.accent.opacity(0.065),in:Capsule())
        }.buttonStyle(.plain)
        .popover(isPresented:$open,arrowEdge:.bottom) {
            SpeakerPickerMenu(query:$query,people:store.allPeople,currentID:speaker.id,
                              busy:store.identityBusy,enabled:canChange,
                              footer:submitted ? store.identityMessage : (canChange ? (speaker.id.hasPrefix("manual:") ? "修改本段姓名，已保存的人员可再次选择" : "后续将自动应用修改后的名称；选择已有人员会合并身份") : "等待说话人识别就绪…"),
                              canUndo:store.current?.canUndoIdentity == true,
                              select: { person in
                                  submitted = true
                                  store.chooseSpeaker(source:speaker.id,person:person)
                                  if !store.identityBusy { open = false }
                              },add: { name in
                                  submitted = true; store.renameInlineSpeaker(speaker.id,name:name)
                                  if !store.identityBusy { open = false }
                              },undo:store.undoSpeakerIdentity)
                .onChange(of:store.identityBusy) { wasBusy,isBusy in
                    // A successful identity update changes the displayed name/ID.
                    // Errors leave the menu open so the response remains visible.
                    if wasBusy && !isBusy && submitted && speaker.name == query.trimmingCharacters(in:.whitespacesAndNewlines) { open = false }
                }
        }
    }
}
