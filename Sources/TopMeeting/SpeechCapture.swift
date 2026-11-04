import AVFoundation
import Speech

// Audio is always recorded, including quiet and overlapping voices. Energy is used
// only to end utterances; it never gates or discards input to the recognizer.
private final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var receiver: ((AVAudioPCMBuffer) -> Void)?
    func setReceiver(_ receiver: ((AVAudioPCMBuffer) -> Void)?) { lock.lock(); defer { lock.unlock() }; self.receiver = receiver }
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var pending: [AVAudioPCMBuffer] = []
    private var pendingDuration: Double = 0
    private var lastSpeech = Date()
    private var level: Double = -90
    private var gain: Float = 1
    private var gainControl = RecognitionGain()
    var onAudio: ((Data,Double) -> Void)?
    func configure(file: AVAudioFile?, gain: Float) {
        lock.lock(); defer { lock.unlock() }
        self.file = file; self.gain = gain; gainControl = RecognitionGain(); pending = []; pendingDuration = 0; lastSpeech = Date(); level = -90
    }
    func snapshot() -> (Double, Date) { lock.lock(); defer { lock.unlock() }; return (level,lastSpeech) }
    @discardableResult func set(_ value: SFSpeechAudioBufferRecognitionRequest?) -> Double {
        lock.lock(); defer { lock.unlock() }
        request = value
        let buffered = pendingDuration
        if let value { pending.forEach { value.append($0) }; pending = []; pendingDuration = 0 }
        return buffered
    }
    func append(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock(); defer { lock.unlock() }
        try file?.write(from:buffer)
        var peak: Float = 0
        if let source = buffer.floatChannelData {
            var mono = [Float](repeating:0,count:Int(buffer.frameLength))
            let channels = Int(buffer.format.channelCount)
            for channel in 0..<channels { for frame in mono.indices {
                let sample = buffer.format.isInterleaved ? source[0][frame*channels + channel] : source[channel][frame]
                if sample.isFinite { peak = max(peak,abs(sample)) }
                mono[frame] += (sample.isFinite ? sample : 0) / Float(channels)
            } }
            let data = mono.withUnsafeBytes { Data($0) }
            onAudio?(data,buffer.format.sampleRate)
        }
        level = AudioSamples.level(buffer)
        let effectiveGain = gainControl.next(level:level,peak:peak,base:gain,duration:Double(buffer.frameLength)/buffer.format.sampleRate)
        if level + 20 * log10(Double(max(1,effectiveGain))) > -58 { lastSpeech = Date() }
        guard let copy = AudioSamples.amplified(buffer,gain:effectiveGain) else {
            // Do not hand a reusable tap buffer to asynchronous recognition.
            throw NSError(domain:"TopMeeting",code:2,userInfo:[NSLocalizedDescriptionKey:"无法复制识别音频缓冲区"])
        }
        if let receiver { receiver(copy) }
        else if let request { request.append(copy) }
        else {
            pending.append(copy); pendingDuration += Double(copy.frameLength) / copy.format.sampleRate
            while pendingDuration > 3, !pending.isEmpty { let old = pending.removeFirst(); pendingDuration -= Double(old.frameLength) / old.format.sampleRate }
        }
    }
}
enum UtteranceBoundary {
    static func shouldFinish(hasText: Bool, age: Double, silence: Double, stable: Double) -> Bool {
        // Partial captions keep updating; only rotate at a sustained pause or
        // before the recognizer's long-running request becomes unreliable.
        age >= 45 || (hasText && age >= 6 && silence >= 2.2 && stable >= 2)
    }
}
@MainActor final class SpeechCapture {
    private let engine = AVAudioEngine()
    private var continuous: (any ContinuousTranscription)?
    private let sink = AudioSink()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer = SFSpeechRecognizer(locale:Locale(identifier:"zh-CN"))
    private var installed = false
    private var ticker: Timer?
    private var generation = UUID()
    private var utterance = UUID()
    private var sessionStart = Date()
    private var utteranceStart = Date()
    private var latest = ""
    private var lastTextChange = Date()
    private var finishingAt: Date?
    private var retryAt: Date?
    private var running = false
    private var pausedAt: Date?
    private var diskFailed = false
    private(set) var contextualTerms: [String] = []
    func setContextualTerms(_ terms: [String]) { contextualTerms = Array(terms.prefix(100)); continuous?.updateTerms(contextualTerms) }
    var onText: ((UUID, String, Bool, TimeInterval) -> Void)?
    var onLevel: ((Double) -> Void)?
    var onStatus: ((String) -> Void)?
    var onAudio: ((Data,Double) -> Void)? { didSet { sink.onAudio = onAudio } }
    var onWords: ((UUID,[SpeechWord]) -> Void)?
    static func supportedLocales() async -> [String] {
        if #available(macOS 26, *), SpeechTranscriber.isAvailable { return await SpeechTranscriber.supportedLocales.map(\.identifier).sorted() }
        return SFSpeechRecognizer.supportedLocales().map(\.identifier).sorted()
    }
    func start(url: URL, gain: Float, device: UInt32, localeIdentifier: String = "zh-CN") async throws {
        recognizer = SFSpeechRecognizer(locale:Locale(identifier:localeIdentifier))
        guard await AVCaptureDevice.requestAccess(for:.audio) else { throw failure("请在系统设置中允许 TopMeeting 使用麦克风。") }
        let auth = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning:$0) } }
        guard auth == .authorized else { throw failure("请在系统设置中允许语音识别。") }

        let input = engine.inputNode
        try AudioDevices.select(device,node:input)
        if input.isVoiceProcessingEnabled { try input.setVoiceProcessingEnabled(false) }
        let format = input.outputFormat(forBus:0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw failure("当前没有可用麦克风，请连接设备后重试。") }
        sink.configure(file:try AVAudioFile(forWriting:url,settings:format.settings),gain:gain)
        sessionStart = Date(); pausedAt = nil; running = true; diskFailed = false
        if #available(macOS 26, *), SpeechTranscriber.isAvailable {
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo:Locale(identifier:localeIdentifier)) else { running = false; sink.configure(file:nil,gain:1); throw failure("本机会议转写不支持所选语言。") }
            let session = ContinuousSpeech(locale:locale,onText:{ [weak self] in self?.onText?($0,$1,$2,$3) },onWords:{ [weak self] in self?.onWords?($0,$1) },onStatus:{ [weak self] in self?.onStatus?($0) })
            continuous = session
            do { try await session.start(terms:contextualTerms) }
            catch { await session.finish(); continuous = nil; sink.configure(file:nil,gain:1); running = false; throw error }
            sink.setReceiver(session.feed)
        } else {
            guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { running = false; sink.configure(file:nil,gain:1); throw failure("所选语言的本机离线识别尚不可用。") }
            beginRecognition()
        }
        let sink = self.sink
        input.installTap(onBus:0,bufferSize:2048,format:format) { [weak self] buffer, _ in
            do { try sink.append(buffer) }
            catch { Task { @MainActor in
                guard let self, !self.diskFailed else { return }; self.diskFailed = true
                self.onStatus?("录音文件写入失败，请停止录音并检查磁盘。")
            } }
        }
        installed = true; engine.prepare()
        do { try engine.start() } catch { await stop(); throw error }
        ticker = Timer.scheduledTimer(withTimeInterval:0.2,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        if AVCaptureDevice.activeMicrophoneMode == .voiceIsolation { onStatus?("系统正启用“语音突显”，可能压低其他人声音。请在控制中心的麦克风模式中切换为“标准”或“宽谱”。") }
        else { onStatus?(continuous != nil ? "会议转写引擎 · 连续识别房间内所有声音" : "兼容转写引擎 · 停顿后自动分段") }
    }
    private func tick() {
        guard running, pausedAt == nil else { return }
        let now = Date(), snapshot = sink.snapshot()
        onLevel?(snapshot.0)
        if continuous != nil { return }
        if let retryAt { if now >= retryAt { self.retryAt = nil; beginRecognition() }; return }
        if let finishingAt {
            if now.timeIntervalSince(finishingAt) > 1.5 { finishLatest(); beginRecognition() }
            return
        }
        let age = now.timeIntervalSince(utteranceStart)
        if UtteranceBoundary.shouldFinish(hasText:!latest.isEmpty,age:age,silence:now.timeIntervalSince(snapshot.1),stable:now.timeIntervalSince(lastTextChange)) {
            finishingAt = now; sink.set(nil); request?.endAudio()
        }
    }
    private func finishLatest() {
        if !latest.isEmpty { onText?(utterance,latest,true,max(0,utteranceStart.timeIntervalSince(sessionStart))) }
    }
    private func beginRecognition() {
        guard running else { return }
        generation = UUID(); let current = generation
        task?.cancel()
        utterance = UUID(); utteranceStart = Date(); latest = ""; finishingAt = nil
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true; req.shouldReportPartialResults = true
        req.taskHint = .dictation; req.addsPunctuation = true
        req.contextualStrings = contextualTerms
        request = req; let buffered = sink.set(req); utteranceStart = Date().addingTimeInterval(-buffered)
        task = recognizer?.recognitionTask(with:req) { [weak self] result,error in
            Task { @MainActor in
                guard let self, self.running, self.generation == current else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if self.latest != text { self.lastTextChange = Date() }
                    self.latest = text
                    let origin = max(0,self.utteranceStart.timeIntervalSince(self.sessionStart))
                    self.onText?(self.utterance,self.latest,result.isFinal,origin)
                    self.onWords?(self.utterance,result.bestTranscription.segments.map { SpeechWord(text:$0.substring,start:origin + $0.timestamp,end:origin + $0.timestamp + $0.duration) })
                    if result.isFinal { self.beginRecognition(); return }
                }
                if error != nil {
                    self.finishLatest(); self.sink.set(nil); self.request?.endAudio()
                    self.generation = UUID(); self.finishingAt = nil; self.retryAt = Date().addingTimeInterval(0.6)
                    self.onStatus?("识别正在恢复连接；原始录音继续保存。")
                }
            }
        }
    }
    @discardableResult func pause() -> Bool {
        guard running, pausedAt == nil else { return false }
        engine.pause(); pausedAt = Date(); onLevel?(-90)
        if continuous == nil {
            finishLatest(); latest = ""; generation = UUID()
            sink.set(nil); request?.endAudio(); task?.cancel()
            retryAt = nil; finishingAt = nil
        }
        return true
    }
    func resume() throws {
        guard running, let pausedAt else { return }
        try engine.start()
        sessionStart = sessionStart.addingTimeInterval(Date().timeIntervalSince(pausedAt))
        self.pausedAt = nil
        if continuous == nil { beginRecognition() }
    }
    func stop() async {
        finishLatest(); running = false; generation = UUID(); ticker?.invalidate(); ticker = nil; retryAt = nil
        engine.stop(); pausedAt = nil
        if installed { engine.inputNode.removeTap(onBus:0); installed = false }
        sink.setReceiver(nil)
        if let continuous { await continuous.finish(); self.continuous = nil }
        sink.set(nil); sink.configure(file:nil,gain:1)
        request?.endAudio(); task?.cancel(); task = nil; request = nil
    }
    private func failure(_ message: String) -> NSError { NSError(domain:"TopMeeting",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
}
