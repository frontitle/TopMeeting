import AVFoundation
import Speech

@MainActor protocol ContinuousTranscription: AnyObject {
    var feed: (AVAudioPCMBuffer) -> Void { get }
    func finish() async
    func updateTerms(_ terms: [String])
}

/// Converts owned buffers on the audio callback; the recognizer consumes them
/// asynchronously. No fixed-duration recognition requests or gaps between them.
@available(macOS 26, *)
private final class AnalyzerAudioInput: @unchecked Sendable {
    private let lock = NSLock()
    private let format: AVAudioFormat
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    let stream: AsyncStream<AnalyzerInput>
    var onError: (@Sendable (String) -> Void)?
    init(format: AVAudioFormat) {
        self.format = format
        let pair = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy:.bufferingOldest(400))
        stream = pair.stream; continuation = pair.continuation
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let continuation else { return }
        if sourceFormat != buffer.format {
            sourceFormat = buffer.format
            converter = AVAudioConverter(from:buffer.format,to:format)
        }
        guard let converter,
              let converted = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(ceil(Double(buffer.frameLength)*format.sampleRate/buffer.format.sampleRate))+32) else {
            onError?("音频格式转换失败，原始录音仍在保存。"); return
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to:converted,error:&error) { _, inputStatus in
            if supplied { inputStatus.pointee = .noDataNow; return nil }
            supplied = true; inputStatus.pointee = .haveData; return buffer
        }
        if status == .error { onError?("音频转换中断，原始录音仍在保存。"); return }
        guard converted.frameLength > 0 else { return }
        if case .dropped = continuation.yield(AnalyzerInput(buffer:converted)) {
            onError?("转写处理落后，部分实时字幕可能缺失；原始录音完整保留。")
        }
    }
    func finish() {
        lock.lock(); defer { lock.unlock() }
        // Flush the resampler's trailing samples before finishing the stream.
        if let converter, let tail = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:4096) {
            var error: NSError?
            _ = converter.convert(to:tail,error:&error) { _, status in status.pointee = .endOfStream; return nil }
            if tail.frameLength > 0 { continuation?.yield(AnalyzerInput(buffer:tail)) }
        }
        continuation?.finish(); continuation = nil
    }
}

@available(macOS 26, *)
@MainActor final class ContinuousSpeech: ContinuousTranscription {
    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private var input: AnalyzerAudioInput?
    private var resultsTask: Task<Void,Never>?
    private var contextTask: Task<Void,Never>?
    private var utterance = UUID()
    private var pendingText = ""
    private var pendingTime: Double = 0
    private let onText: (UUID,String,Bool,Double) -> Void
    private let onWords: (UUID,[SpeechWord]) -> Void
    private let onStatus: (String) -> Void
    init(locale: Locale, onText: @escaping (UUID,String,Bool,Double) -> Void,
         onWords: @escaping (UUID,[SpeechWord]) -> Void, onStatus: @escaping (String) -> Void) {
        transcriber = SpeechTranscriber(locale:locale,preset:.timeIndexedProgressiveTranscription)
        analyzer = SpeechAnalyzer(modules:[transcriber])
        self.onText = onText; self.onWords = onWords; self.onStatus = onStatus
    }
    func start(terms: [String]) async throws {
        if let download = try await AssetInventory.assetInstallationRequest(supporting:[transcriber]) {
            onStatus("正在准备本机会议转写模型…")
            try await download.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:[transcriber]) else {
            throw NSError(domain:"TopMeeting",code:1,userInfo:[NSLocalizedDescriptionKey:"本机会议转写不支持当前音频格式。"])
        }
        let context = AnalysisContext(); context.contextualStrings[.general] = terms
        try await analyzer.setContext(context)
        let input = AnalyzerAudioInput(format:format)
        input.onError = { [weak self] message in Task { @MainActor in self?.onStatus(message) } }
        self.input = input
        try await analyzer.prepareToAnalyze(in:format)
        resultsTask = Task { [weak self, transcriber] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    pendingText = text; pendingTime = result.range.start.seconds
                    onText(utterance,text,result.isFinal,pendingTime)
                    let words = result.text.runs.compactMap { run -> SpeechWord? in
                        guard let range = run.audioTimeRange else { return nil }
                        return SpeechWord(text:String(result.text[run.range].characters),start:range.start.seconds,end:CMTimeRangeGetEnd(range).seconds)
                    }
                    onWords(utterance,words)
                    if result.isFinal { utterance = UUID(); pendingText = "" }
                }
            } catch {
                if !Task.isCancelled { self?.onStatus("会议转写中断：\(error.localizedDescription)。原始录音仍在保存，请结束后重试。") }
            }
        }
        try await analyzer.start(inputSequence:input.stream)
    }
    var feed: (AVAudioPCMBuffer) -> Void {
        let input = input
        return { buffer in input?.append(buffer) }
    }
    func updateTerms(_ terms: [String]) {
        contextTask?.cancel()
        contextTask = Task {
            let context = AnalysisContext(); context.contextualStrings[.general] = terms
            do { try Task.checkCancellation(); try await analyzer.setContext(context) }
            catch { if !Task.isCancelled { onStatus("术语更新未生效，将在下一次录音重新加载。") } }
        }
    }
    func finish() async {
        contextTask?.cancel(); input?.finish()
        // Cancellation releases a stalled framework instead of hanging End Meeting.
        let watchdog = Task { [analyzer] in
            do { try await Task.sleep(nanoseconds:8_000_000_000); await analyzer.cancelAndFinishNow() }
            catch { }
        }
        do { try await analyzer.finalizeAndFinishThroughEndOfInput() }
        catch { onStatus("转写收尾未完成，已保留现有字幕与原始录音。") }
        await resultsTask?.value
        watchdog.cancel()
        if !pendingText.isEmpty { onText(utterance,pendingText,true,pendingTime); pendingText = "" }
        resultsTask = nil; input = nil
    }
}
