import Foundation
import Darwin

/// All native meeting updates, including receipts from document services, use this archive.
final class MeetingArchive {
    let directory: URL
    private var last: Data?
    private var ready = false
    private(set) var recovered = false
    private var file: URL { directory.appendingPathComponent("meetings.json") }
    private var backup: URL { directory.appendingPathComponent("meetings.previous.json") }
    init(directory: URL) { self.directory = directory }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        let fd = Darwin.open(directory.appendingPathComponent(".meeting-write.lock").path,O_CREAT | O_RDWR,0o600)
        guard fd >= 0 else { throw Gateway.error("无法打开会议资料库锁") }
        defer { Darwin.close(fd) }
        guard flock(fd,LOCK_EX | LOCK_NB) == 0 else { throw Gateway.error("另一进程正在保存会议，请稍后重试") }
        defer { flock(fd,LOCK_UN) }
        return try operation()
    }

    private func read(_ url: URL) throws -> Data? {
        do { return try Data(contentsOf:url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
    }

    func load() throws -> [Meeting] {
        try locked {
            let current = try read(file)
            if let current, let decoded = try? JSONDecoder().decode([Meeting].self,from:current) {
                last = current; ready = true; return decoded
            }
            let previous = try read(backup)
            if previous == nil && current == nil { ready = true; return [] }
            guard let previous, let decoded = try? JSONDecoder().decode([Meeting].self,from:previous) else {
                throw Gateway.error("会议文件无法读取，已保留原件。请恢复备份后重新打开。")
            }
            if let current {
                try current.write(to:directory.appendingPathComponent("meetings.unreadable-"+UUID().uuidString),options:.atomic)
            }
            try previous.write(to:file,options:.atomic)
            last = previous; ready = true; recovered = true; return decoded
        }
    }

    func save(_ meetings: [Meeting]) throws {
        guard ready else { throw Gateway.error("会议资料尚未成功读取，保存已暂停") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let committed = meetings.map { meeting -> Meeting in
            var snapshot = meeting
            snapshot.lines.removeAll { $0.live == true }
            return snapshot
        }
        let next = try encoder.encode(committed)
        try locked {
            guard try read(file) == last else { throw Gateway.error("会议文件已在其他位置修改，请重新打开客户端") }
            if next == last { return }
            if let last { try last.write(to:backup,options:.atomic) }
            try next.write(to:file,options:.atomic)
            last = next
        }
    }
}
