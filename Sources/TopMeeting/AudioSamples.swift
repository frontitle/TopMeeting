import AVFoundation

enum AudioSamples {
    static func level(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let source = buffer.floatChannelData, buffer.frameLength > 0 else { return -90 }
        let planes = buffer.format.isInterleaved ? 1 : Int(buffer.format.channelCount)
        let samples = Int(buffer.frameLength) * (buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1)
        guard planes > 0, samples > 0 else { return -90 }
        var sum: Double = 0
        for channel in 0..<planes {
            for frame in 0..<samples {
                let value = source[channel][frame]
                if value.isFinite { sum += Double(value) * Double(value) }
            }
        }
        return max(-90,min(6,20 * log10(max(0.00001,sqrt(sum / Double(planes * samples))))))
    }
    static func amplified(_ buffer: AVAudioPCMBuffer,gain: Float) -> AVAudioPCMBuffer? {
        guard let source = buffer.floatChannelData,
              let copy = AVAudioPCMBuffer(pcmFormat:buffer.format,frameCapacity:buffer.frameLength),
              let target = copy.floatChannelData else { return nil }
        copy.frameLength = buffer.frameLength
        let planes = buffer.format.isInterleaved ? 1 : Int(buffer.format.channelCount)
        let samples = Int(buffer.frameLength) * (buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1)
        for channel in 0..<planes {
            for frame in 0..<samples {
                let sample = source[channel][frame]
                target[channel][frame] = sample.isFinite ? max(-0.98,min(0.98,sample * max(0,min(6,gain)))) : 0
            }
        }
        return copy
    }
}

/// Gentle compensation for distant voices, bounded to the existing 6x ceiling.
/// Never gates samples; peak headroom prevents a nearby voice being clipped.
struct RecognitionGain {
    private var smoothed: Float = 1
    mutating func next(level: Double, peak: Float, base: Float, duration: Double) -> Float {
        let baseline = max(1,min(6,base))
        let desired = level > -65 ? max(baseline,min(6,Float(pow(10,(-28-level)/20)))) : baseline
        let alpha = Float(1-exp(-max(0,duration)/0.35))
        smoothed += (desired-smoothed)*alpha
        return min(max(baseline,smoothed),0.98/max(0.000001,peak))
    }
}
