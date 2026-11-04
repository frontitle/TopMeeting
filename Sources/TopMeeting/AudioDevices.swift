import CoreAudio
import AudioToolbox
import AVFoundation

struct Microphone: Identifiable {
    let id: AudioDeviceID
    let name: String
}
enum AudioDevices {
    static func inputs() -> [Microphone] {
        var address = AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDevices,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating:0,count:Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = devices.withUnsafeMutableBytes { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,$0.baseAddress!) }
        guard status == noErr else { return [] }
        return devices.compactMap { device in
            var streams = AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyStreams,mScope:kAudioDevicePropertyScopeInput,mElement:kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device,&streams,0,nil,&streamSize) == noErr, streamSize > 0 else { return nil }
            var nameAddress = AudioObjectPropertyAddress(mSelector:kAudioObjectPropertyName,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            var name: CFString = "麦克风" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            let status = withUnsafeMutablePointer(to:&name) { AudioObjectGetPropertyData(device,&nameAddress,0,nil,&nameSize,$0) }
            guard status == noErr else { return nil }
            return Microphone(id:device,name:name as String)
        }
    }
    static func select(_ device: AudioDeviceID, node: AVAudioInputNode) throws {
        guard device != 0 else { return }
        guard let unit = node.audioUnit else { throw Gateway.error("当前音频输入不可用。") }
        var selected = device
        let status = AudioUnitSetProperty(unit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&selected,UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw Gateway.error("无法打开所选麦克风（\(status)），请重新选择可用设备。") }
    }
}
