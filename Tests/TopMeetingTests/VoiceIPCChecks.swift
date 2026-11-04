import Foundation
import AVFoundation

@main struct VoiceIPCChecks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:temporary) }
        let runtime = VoiceRuntime()
        var packets: [VoicePacket] = []
        var failure: String?
        runtime.onPacket = { packets.append($0) }
        runtime.onFailure = { failure = $0 }
        try runtime.start(profiles:temporary.appendingPathComponent("profiles.json"),resourceOverride:root.appendingPathComponent("dist/TopMeeting.app/Contents/Resources"))
        func wait(_ predicate: () -> Bool) async throws {
            for _ in 0..<1000 {
                if predicate() { return }
                if let failure { throw Gateway.error(failure) }
                try await Task.sleep(nanoseconds:20_000_000)
            }
            throw Gateway.error("Native voice IPC timed out")
        }
        try await wait { packets.contains { $0.type == "ready" } }
        func samples(_ name: String, prefix: String = "heldout") throws -> [Float] {
            let file = try AVAudioFile(forReading:root.appendingPathComponent("tests_audio/\(prefix)-\(name).wav"))
            let buffer = AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length))!
            try file.read(into:buffer)
            return Array(UnsafeBufferPointer(start:buffer.floatChannelData![0],count:Int(buffer.frameLength)))
        }
        runtime.session("discovery",meetingID:"native-meeting")
        let discovery = try samples("a",prefix:"enroll") + samples("b",prefix:"enroll")
        for start in stride(from:0,to:discovery.count,by:16000) {
            let chunk = Array(discovery[start..<min(start+16000,discovery.count)])
            runtime.audio(chunk.withUnsafeBytes { Data($0) },rate:16000)
        }
        runtime.flush()
        try await wait { packets.contains { $0.sessionID == "discovery" && $0.requestID == "final-flush" } }
        let detected = packets.last(where:{$0.sessionID == "discovery" && $0.requestID == "final-flush"})!.events ?? []
        guard let first = detected.first(where:{$0.start<2 && !$0.overlap})?.speakerIDs.first,
              let second = detected.first(where:{$0.start>4.5 && !$0.overlap})?.speakerIDs.first, first != second else { throw Gateway.error("Automatic speaker discovery failed") }
        for (identity,name) in [(first,"a"),(second,"b")] {
            runtime.command(["command":"label","meetingID":"native-meeting","source":identity,"name":"测试声纹 \(name)","requestID":"label-\(name)"])
            try await wait { packets.contains { $0.requestID == "label-\(name)" } }
            guard packets.last(where:{$0.requestID == "label-\(name)"})?.type == "identity" else { throw Gateway.error("Quick speaker naming failed") }
        }
        let a = try samples("a"), b = try samples("b")
        runtime.session("native-alternating",meetingID:"native-meeting",offset:8)
        let alternating = a + b
        for start in stride(from:0,to:alternating.count,by:16000) {
            let chunk = Array(alternating[start..<min(start+16000,alternating.count)])
            runtime.audio(chunk.withUnsafeBytes { Data($0) },rate:16000)
        }
        runtime.flush()
        try await wait { packets.contains { $0.sessionID == "native-alternating" && $0.requestID == "final-flush" } }
        let names = Set(packets.filter { $0.sessionID == "native-alternating" }.flatMap { ($0.events ?? []).flatMap(\.speakers) })
        guard names.contains("测试声纹 a"), names.contains("测试声纹 b") else { throw Gateway.error("Native stream failed held-out speaker matching") }
        let personA = packets.last(where:{$0.requestID == "label-a"})!.mappings![first]!
        runtime.command(["command":"label","meetingID":"native-meeting","source":second,"target":personA,"requestID":"merge-ipc"])
        try await wait { packets.contains { $0.requestID == "merge-ipc" } }
        guard packets.last(where:{$0.requestID == "merge-ipc"})?.type == "identity" else { throw Gateway.error("Merge IPC failed") }
        runtime.command(["command":"undo","meetingID":"native-meeting","requestID":"undo-ipc"])
        try await wait { packets.contains { $0.requestID == "undo-ipc" } }
        guard packets.last(where:{$0.requestID == "undo-ipc"})?.undone == true else { throw Gateway.error("Merge undo IPC failed") }
        runtime.command(["command":"contact","meetingID":"native-meeting","name":"待采集人员","requestID":"contact-ipc"])
        try await wait { packets.contains { $0.requestID == "contact-ipc" } }
        guard packets.last(where:{$0.requestID == "contact-ipc"})?.personID != nil else { throw Gateway.error("Inline new person IPC failed") }
        runtime.command(["command":"label","meetingID":"native-meeting","source":first,"name":"新建人员","newPerson":true,"requestID":"new-person-ipc"])
        try await wait { packets.contains { $0.requestID == "new-person-ipc" } }
        guard let created = packets.last(where:{$0.requestID == "new-person-ipc"}), created.localOnly == true, created.profiles?.contains(where:{$0.name == "测试声纹 a"}) == true else { throw Gateway.error("New-person flow renamed an existing person") }
        runtime.command(["command":"undo","meetingID":"native-meeting","requestID":"undo-new-person-ipc"])
        try await wait { packets.contains { $0.requestID == "undo-new-person-ipc" } }
        runtime.session("native-overlap",meetingID:"native-meeting",offset:14)
        let mixture = zip(a,b).map { ($0 + $1) * 0.5 }
        for start in stride(from:0,to:mixture.count,by:16000) {
            let chunk = Array(mixture[start..<min(start+16000,mixture.count)])
            runtime.audio(chunk.withUnsafeBytes { Data($0) },rate:16000)
        }
        runtime.flush()
        try await wait { packets.contains { $0.sessionID == "native-overlap" && $0.requestID == "final-flush" } }
        guard packets.filter({$0.sessionID == "native-overlap"}).contains(where:{($0.events ?? []).contains(where:{$0.overlap})}) else { throw Gateway.error("Native overlap event not delivered") }
        print("PASS: bundled model readiness, automatic discovery IPC, quick naming without pre-enrollment, real-speech streaming, held-out identity delivery, merge/undo IPC, inline new-person isolation, contact creation IPC, overlap event delivery, session isolation, end-of-recording flush")
    }
}
