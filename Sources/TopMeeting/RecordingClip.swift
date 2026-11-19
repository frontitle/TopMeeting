import AVFoundation

/// Transcript timestamps use cumulative recording time across resumed sessions.
struct RecordingClip {
    let url: URL
    let offset: TimeInterval
    let duration: TimeInterval

    static func locate(paths: [String], from start: TimeInterval, until end: TimeInterval?) throws -> Self {
        var offset = max(0, start)
        for path in paths {
            let url = URL(fileURLWithPath:path)
            let file = try AVAudioFile(forReading:url)
            let length = Double(file.length) / file.processingFormat.sampleRate
            if offset < length {
                let available = length - offset
                let duration = min(available, end.map { $0 - start } ?? available)
                guard duration > 0 else { break }
                return Self(url:url, offset:offset, duration:duration)
            }
            offset -= length
        }
        throw Gateway.error("这个时间点没有可播放的录音。")
    }
}
