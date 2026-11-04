import AppKit
import SwiftUI
func clock(_ seconds: Double) -> String { String(format:"%02d:%02d",Int(seconds)/60,Int(seconds)%60) }
@MainActor final class MeetingStore: ObservableObject {
    var listeningSpeaker = "说话人 1"
    @Published var recording = false
    @Published var recordingPaused = false
    @Published var ending = false
    @Published var elapsed: Double = 183
    @Published var inputLevels: [Double] = (0..<28).map { -60 + Double(($0 * 11) % 40) }
    func toggleRecordingPause() { recordingPaused.toggle() }
    @Published var liveCaption = "这是一段测试字幕，检查可拖动区域。"
    @Published var inputLevel = -36.0
}
@main struct ListeningPanelChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let store = MeetingStore(), controller = ListeningPanelController()
        var opened = 0
        controller.connect(store,showMain:{ opened += 1 })
        let panel = app.windows.first { $0.title == "TopMeeting 实时聆听" }!
        precondition(panel.frame.width == 420 && panel.frame.height == 140)
        precondition(panel.level == .floating && !panel.hidesOnDeactivate)
        precondition(panel.collectionBehavior.contains(.canJoinAllSpaces))
        store.recording = true
        precondition(panel.isVisible)
        let host = panel.contentView!
        host.layoutSubtreeIfNeeded()
        for point in [NSPoint(x:30,y:30),NSPoint(x:210,y:65),NSPoint(x:300,y:65)] {
            precondition(host.hitTest(point) === host,"SwiftUI swallowed the native drag target")
        }
        let button = host.subviews.compactMap { $0 as? NSButton }.first!
        precondition(button.frame.midX > host.bounds.width-60,"Pause button was not placed at trailing edge")
        let center = host.convert(NSPoint(x:button.bounds.midX,y:button.bounds.midY),from:button)
        precondition(host.hitTest(center) === button,"Drag host swallowed pause button")
        button.performClick(nil); precondition(store.recordingPaused,"Pause button failed")
        button.performClick(nil); precondition(!store.recordingPaused,"Resume button failed")
        store.ending = true; precondition(!button.isEnabled,"Pause remained enabled while finishing")
        store.ending = false
        let doubleClick = NSEvent.mouseEvent(with:.leftMouseDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:panel.windowNumber,context:nil,eventNumber:2,clickCount:2,pressure:1)!
        host.mouseDown(with:doubleClick); precondition(opened == 1,"Double click did not open main window")
        if CommandLine.arguments.count > 1 {
            RunLoop.current.run(until:Date().addingTimeInterval(0.3))
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds)!
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
        }
        store.recording = false
        precondition(!panel.isVisible)
        print("PASS: compact bounds, all-space floating panel, show/hide lifecycle, native drag hit routing, pause/resume button routing, end guard, double-click navigation")
    }
}
