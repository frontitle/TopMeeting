// Run with scripts/check-continuous-speech.sh /absolute/path/to/sample.wav
import Foundation
import AVFoundation
struct SpeechWord { var text: String; var start: Double; var end: Double }
@main struct ContinuousSpeechChecks {
    @MainActor static func main() async throws {
        guard #available(macOS 26, *) else { fatalError("Requires macOS 26") }
        let file = try AVAudioFile(forReading:URL(fileURLWithPath:CommandLine.arguments[1]))
        let started = Date()
        var firstPartial: Double?
        var finals: [UUID:String] = [:]
        var partials = 0
        var wordCount = 0
        var statuses: [String] = []
        let session = ContinuousSpeech(locale:Locale(identifier:"zh-CN"),onText: { id,text,final,time in
            if final { finals[id] = text }
            else { partials += 1; if firstPartial == nil && !text.isEmpty { firstPartial = Date().timeIntervalSince(started) } }
            precondition(time.isFinite && time >= 0)
        },onWords: { _,words in
            wordCount += words.count
            precondition(words.allSatisfy { $0.start.isFinite && $0.end >= $0.start })
        },onStatus: { statuses.append($0) })
        try await session.start(terms:["会议"])
        let feed = session.feed
        var gain = RecognitionGain()
        let readSize = AVAudioFrameCount(file.processingFormat.sampleRate * 0.1)
        while file.framePosition < file.length {
            let buffer = AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:readSize)!
            try file.read(into:buffer)
            let level = AudioSamples.level(buffer)
            var peak: Float = 0
            for c in 0..<Int(buffer.format.channelCount) {
                for i in 0..<Int(buffer.frameLength) { peak = max(peak,abs(buffer.floatChannelData![c][i])) }
            }
            let value = gain.next(level:level,peak:peak,base:3,duration:0.1)
            feed(AudioSamples.amplified(buffer,gain:value)!)
            try await Task.sleep(nanoseconds:100_000_000)
        }
        let beforeDrain = finals.count
        await session.finish()
        let count = finals.values.reduce(0) { $0 + $1.count }
        precondition(partials > 0 && count > 40 && wordCount > 0,"Real recording did not produce continuous timestamped speech")
        let metrics: [String:Any] = ["partials":partials,"first_partial_seconds":firstPartial ?? -1,"final_segments":finals.count,"finals_before_stop":beforeDrain,"final_characters":count,"word_updates":wordCount,"elapsed":Date().timeIntervalSince(started),"statuses":statuses]
        let data = try JSONSerialization.data(withJSONObject:metrics,options:[.prettyPrinted,.sortedKeys])
        if CommandLine.arguments.count > 2 { try data.write(to:URL(fileURLWithPath:CommandLine.arguments[2])) }
        print(String(decoding:data,as:UTF8.self))
    }
}
