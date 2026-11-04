import Foundation
import AVFoundation

struct VoiceProfile: Codable, Identifiable {
    var id: String
    var name: String
    var seconds: Double
}
struct VoiceTurn: Codable, Identifiable, Equatable {
    var start: Double
    var end: Double
    var speakers: [String]
    var speakerIDs: [String]
    var confidence: Double
    var overlap: Bool
    var sourceIDs: [String]? = nil
    var id: String { "\(Int(start*1000))-\(Int(end*1000))-\(speakerIDs.joined(separator:"-"))" }
}
struct VoicePacket: Decodable {
    var type: String
    var profiles: [VoiceProfile]?
    var events: [VoiceTurn]?
    var replaceFrom: Double?
    var end: Double?
    var inferenceSeconds: Double?
    var message: String?
    var requestID: String?
    var sessionID: String?
    var meetingID: String?
    var mappings: [String:String]?
    var names: [String:String]?
    var learned: Int?
    var quarantined: Int?
    var canUndo: Bool?
    var undone: Bool?
    var localOnly: Bool?
    var personID: String?
    var personName: String?
}

// Bound the pipe backlog: the audio render thread must never wait for inference.
final class VoiceRuntime: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let writer = DispatchQueue(label:"TopMeeting.voice.write")
    private let lock = NSLock()
    private var pendingBytes = 0
    private var queuedAudio = Data()
    private var currentRate = 0.0
    private var activeSession = ""
    func session(_ id: String, meetingID: String? = nil, offset: Double = 0) { lock.lock(); activeSession = id; queuedAudio = Data(); lock.unlock(); command(["command":"reset","meetingID":meetingID ?? id,"offset":offset]) }
    var onPacket: (@MainActor (VoicePacket) -> Void)?
    var onFailure: (@MainActor (String) -> Void)?
    var isRunning: Bool { process.isRunning }
    func start(profiles: URL, resourceOverride: URL? = nil) throws {
        guard !process.isRunning else { return }
        guard let resources = resourceOverride ?? Bundle.main.resourceURL else { throw Gateway.error("声纹资源目录不可用。") }
        let runtime = resources.appendingPathComponent("VoiceRuntime/bin/python3")
        let script = resources.appendingPathComponent("voice_engine/engine.py")
        guard FileManager.default.fileExists(atPath:runtime.path), FileManager.default.fileExists(atPath:script.path) else { throw Gateway.error("本构建未包含声纹引擎，请重新打包应用。") }
        process.executableURL = runtime
        process.arguments = ["-u",script.path,resources.appendingPathComponent("voice_engine/models").path,profiles.path]
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        var env = ProcessInfo.processInfo.environment
        env["PYTHONDONTWRITEBYTECODE"] = "1"; env["PYTHONUNBUFFERED"] = "1"; env["PYTHONNOUSERSITE"] = "1"
        env["OMP_NUM_THREADS"] = "2"; process.environment = env
        errors.fileHandleForReading.readabilityHandler = { handle in if handle.availableData.isEmpty { handle.readabilityHandler = nil } }
        try process.run()
        let handle = output.fileHandleForReading
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            var buffer = Data()
            while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of:10) {
                        let line = buffer.prefix(upTo:newline); buffer.removeSubrange(...newline)
                        if let packet = try? JSONDecoder().decode(VoicePacket.self,from:line) {
                            Task { @MainActor [weak self] in self?.onPacket?(packet) }
                        }
                    }
            }
            Task { @MainActor [weak self] in self?.onFailure?("声纹引擎已退出。录音与文字识别仍可继续，请重新打开应用恢复声纹分析。") }
        }
    }
    func command(_ object: [String:Any]) {
        var object = object
        lock.lock(); let session = activeSession; lock.unlock()
        if ["audio","reset","flush"].contains(object["command"] as? String ?? "") { object["sessionID"] = session }
        guard let data = try? JSONSerialization.data(withJSONObject:object) else { return }
        writer.async { [weak self] in
            guard let self, self.process.isRunning else { return }
            do { try self.input.fileHandleForWriting.write(contentsOf:data + Data([10])) }
            catch { Task { @MainActor [weak self] in self?.onFailure?("声纹分析通道中断，请重新打开应用。") } }
        }
    }
    func audio(_ data: Data,rate: Double) {
        lock.lock()
        queuedAudio.append(data); currentRate = rate
        guard queuedAudio.count >= Int(rate)*4 else { lock.unlock(); return }
        let chunk = queuedAudio; queuedAudio = Data()
        guard pendingBytes < 4_000_000 else {
            lock.unlock()
            Task { @MainActor [weak self] in self?.onFailure?("声纹分析未跟上录音，部分声音未标记。原音与转写继续保存。") }
            return
        }
        pendingBytes += chunk.count; let session = activeSession; lock.unlock()
        writer.async { [weak self] in
            guard let self else { return }
            defer { self.lock.lock(); self.pendingBytes -= chunk.count; self.lock.unlock() }
            guard self.process.isRunning else { return }
            let object: [String:Any] = ["command":"audio","pcm":chunk.base64EncodedString(),"rate":Int(rate),"sessionID":session]
            guard let message = try? JSONSerialization.data(withJSONObject:object) else { return }
            try? self.input.fileHandleForWriting.write(contentsOf:message + Data([10]))
        }
    }
    func reset() {
        lock.lock(); queuedAudio = Data(); lock.unlock()
        command(["command":"reset"])
    }
    func flush() {
        lock.lock(); let remaining = queuedAudio; let rate = currentRate; queuedAudio = Data(); lock.unlock()
        if !remaining.isEmpty { command(["command":"audio","pcm":remaining.base64EncodedString(),"rate":Int(rate)]) }
        command(["command":"flush","requestID":"final-flush"])
    }
    deinit {
        errors.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}

