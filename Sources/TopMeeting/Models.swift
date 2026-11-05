import Foundation
import Security

struct SpeechWord: Codable, Equatable {
    var text: String
    var start: Double
    var end: Double
}
struct DisplaySpeech: Identifiable {
    var id: String
    var source: Line
    var time: Double
    var text: String
    var speaker: String
    var overlap: Bool
    var confidence: Double
    var speakerIDs: [String] = []
    var speakerNames: [String:String] = [:]
    var sourceRange: NSRange? = nil
}
struct Line: Codable, Identifiable, Equatable {
    var id = UUID()
    var time: TimeInterval
    var speaker: String
    var text: String
    var original: String?
    var live: Bool?
    var words: [SpeechWord]?
    var inlineCorrected: Bool?
    var personID: String?
}
struct ChatMessage: Codable, Identifiable {
    var id = UUID()
    var role: String
    var text: String
    var state = "complete"
}
struct MeetingDocumentLink: Codable {
    var status: String
    var url: String?
    var detail: String?
}

struct Meeting: Codable, Identifiable {
    var id = UUID()
    var title = "未命名会议"
    var date = Date()
    var lines: [Line] = []
    var notes = ""
    var context = ""
    var corrections: [TermCorrection]?
    var audioPath: String?
    var audioSegments: [String]?
    var duration: TimeInterval = 0
    var deletedAt: Date?
    var voiceTurns: [VoiceTurn]?
    var voiceAliases: [String:String]?
    var voiceNames: [String:String]?
    var canUndoIdentity: Bool?
    var messages: [ChatMessage]?
    var summaryState: String?
    var summaryLanguage: String?
    var summarizedAt: Date?
    var summaryFingerprint: String?
    var documentLinks: [String:MeetingDocumentLink]?
    var feishu: FeishuDocument?
    var conversation: [ChatMessage] { messages ?? [] }
    var userClarifications: String {
        conversation.filter { $0.role == "user" }.map(\.text).joined(separator:"\n")
    }
    func resolvedSpeaker(_ identity: String) -> String {
        var result = identity, seen = Set<String>()
        while let target = voiceAliases?[result], !seen.contains(result) { seen.insert(result); result = target }
        return result
    }
    func namesFor(_ turn: VoiceTurn?) -> (ids:[String],text:String) {
        guard let turn else { return ([],"未标记") }
        var ids: [String] = [], names: [String] = []
        for (index,rawID) in (turn.sourceIDs ?? turn.speakerIDs).enumerated() {
            let id = resolvedSpeaker(rawID)
            if !ids.contains(id) {
                ids.append(id)
                names.append(voiceNames?[id] ?? (index < turn.speakers.count ? turn.speakers[index] : "未标记"))
            }
        }
        return (ids,names.joined(separator:" + "))
    }
    /// Voice analysis trails audio slightly. Never label a fresh utterance with
    /// an identity left over from a long pause or a future replay event.
    func listeningSpeaker(at time: TimeInterval) -> String {
        guard let turn = (voiceTurns ?? []).filter({ $0.start <= time && $0.end >= time - 3 })
            .max(by:{ $0.end < $1.end }) else { return "识别说话人…" }
        let identity = namesFor(turn)
        guard identity.ids.contains(where:{ $0 != "unknown" }) else { return "说话人待确认" }
        return turn.overlap ? "重叠 · " + identity.text : identity.text
    }
    var attributedLines: [DisplaySpeech] {
        lines.flatMap { line -> [DisplaySpeech] in
            // An explicit human correction remains authoritative.
            guard (line.original == nil || line.inlineCorrected == true), line.speaker == "未标记", let words = line.words, !words.isEmpty else {
                let lineEnd = line.words?.last?.end ?? (line.time + 0.1)
                let relevant = line.words == nil ? [] : (voiceTurns ?? []).filter { $0.start < lineEnd && $0.end > line.time }
                let turn = relevant.first
                let hasOverlap = relevant.contains { $0.overlap }
                let personID = line.personID.map { resolvedSpeaker($0) }
                let displayName = personID.flatMap { voiceNames?[$0] } ?? (line.speaker == "未标记" ? namesFor(turn).text : line.speaker)
                return [DisplaySpeech(id:line.id.uuidString,source:line,time:line.time,text:line.text,speaker:displayName,overlap:hasOverlap,confidence:turn?.confidence ?? 0,speakerIDs:personID.map { [$0] } ?? namesFor(turn).ids,sourceRange:NSRange(location:0,length:(line.text as NSString).length))]
            }
            var groups: [DisplaySpeech] = []
            let source = line.text as NSString
            var cursor = 0
            for word in words {
                let found = source.range(of:word.text,range:NSRange(location:cursor,length:source.length-cursor))
                guard found.location != NSNotFound else { continue }
                let span = NSRange(location:cursor,length:NSMaxRange(found)-cursor)
                cursor = NSMaxRange(found)
                let midpoint = (word.start + word.end)/2
                let turn = (voiceTurns ?? []).first { $0.start <= midpoint && $0.end > midpoint }
                let identity = namesFor(turn)
                let speaker = identity.text
                let overlap = turn?.overlap ?? false
                if let last = groups.last, last.speaker == speaker, last.overlap == overlap {
                    let start = groups[groups.count-1].sourceRange?.location ?? span.location
                    let combined = NSRange(location:start,length:NSMaxRange(span)-start)
                    groups[groups.count-1].text = source.substring(with:combined)
                    groups[groups.count-1].sourceRange = combined
                } else {
                    groups.append(DisplaySpeech(id:"\(line.id)-\(groups.count)",source:line,time:word.start,text:source.substring(with:span),speaker:speaker,overlap:overlap,confidence:turn?.confidence ?? 0,speakerIDs:identity.ids,sourceRange:span))
                }
            }
            if groups.isEmpty {
                return [DisplaySpeech(id:line.id.uuidString,source:line,time:line.time,text:line.text,speaker:line.speaker,overlap:false,confidence:0,sourceRange:NSRange(location:0,length:source.length))]
            }
            if !groups.isEmpty, cursor < source.length {
                groups[groups.count-1].text += source.substring(from:cursor)
                if let span = groups[groups.count-1].sourceRange { groups[groups.count-1].sourceRange = NSRange(location:span.location,length:source.length-span.location) }
            }
            return groups
        }
    }
    /// The transcript is one immutable-boundary row per finalized ASR paragraph.
    /// Acoustic spans annotate the header, never split the visible source text.
    var transcriptParagraphs: [DisplaySpeech] {
        var stable = self
        stable.lines = lines.filter { $0.live != true }
        let spans = Dictionary(grouping:stable.attributedLines,by:{ $0.source.id })
        var labels = voiceNames ?? [:]
        for turn in voiceTurns ?? [] {
            for (index,rawID) in (turn.sourceIDs ?? turn.speakerIDs).enumerated() {
                let id = resolvedSpeaker(rawID)
                if labels[id] == nil, index < turn.speakers.count { labels[id] = turn.speakers[index] }
            }
        }
        return stable.lines.map { line in
            let pieces = spans[line.id] ?? []
            var ids: [String] = []
            var names: [String] = []
            for piece in pieces {
                for id in piece.speakerIDs where id != "unknown" && !ids.contains(id) { ids.append(id) }
                if piece.speakerIDs.count == 1, let id = piece.speakerIDs.first, id != "unknown" {
                    labels[id] = piece.speaker
                }
            }
            if line.speaker != "未标记", line.personID == nil { ids = [] }
            for id in ids { names.append(labels[id] ?? "未标记") }
            let name = names.isEmpty ? (pieces.first?.speaker ?? line.speaker) : names.joined(separator:" + ")
            return DisplaySpeech(id:line.id.uuidString,source:line,time:line.time,text:line.text,
                                 speaker:name,overlap:pieces.contains { $0.overlap },
                                 confidence:pieces.map(\.confidence).min() ?? 0,speakerIDs:ids,
                                 speakerNames:labels.filter { ids.contains($0.key) },
                                 sourceRange:NSRange(location:0,length:(line.text as NSString).length))
        }
    }
    mutating func replaceVoiceTurns(_ events: [VoiceTurn],from: Double) {
        var kept = (voiceTurns ?? []).filter { $0.end <= from }
        for var crossing in (voiceTurns ?? []) where crossing.start < from && crossing.end > from { crossing.end = from; kept.append(crossing) }
        voiceTurns = (kept + events).sorted { $0.start < $1.start }
    }
    mutating func acceptSpeech(id: UUID,text: String,final: Bool,time: TimeInterval) {
        if let index = lines.firstIndex(where:{$0.id == id}) {
            if lines[index].original == nil { lines[index].text = text }
            lines[index].live = !final
        } else if !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            lines.append(Line(id:id,time:time,speaker:"未标记",text:text,live:!final))
        }
    }
}
enum Vault {
    static func read(account: String = "token") -> String {
        let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"com.topmeeting.gateway", kSecAttrAccount as String:account, kSecReturnData as String:true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data:data, encoding:.utf8) ?? ""
    }
    static func save(_ token: String,account: String = "token") throws {
        let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"com.topmeeting.gateway", kSecAttrAccount as String:account]
        if token.isEmpty { SecItemDelete(q as CFDictionary); return }
        let data = Data(token.utf8)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q; add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain:"Keychain", code:Int(status), userInfo:[NSLocalizedDescriptionKey:"无法保存连接令牌（\(status)）"]) }
    }
}
func clock(_ seconds: TimeInterval) -> String {
    let n = max(0, Int(seconds)); return String(format:"%02d:%02d", n / 60, n % 60)
}


/// Active recording time excludes pauses, matching the continuous audio file.
struct RecordingClock {
    private var began: Date?
    private var pausedAt: Date?
    private var pausedDuration: TimeInterval = 0
    mutating func start(at date: Date = Date()) { began = date; pausedAt = nil; pausedDuration = 0 }
    mutating func pause(at date: Date = Date()) { if began != nil && pausedAt == nil { pausedAt = date } }
    mutating func resume(at date: Date = Date()) {
        if let pausedAt { pausedDuration += max(0,date.timeIntervalSince(pausedAt)); self.pausedAt = nil }
    }
    func elapsed(at date: Date = Date()) -> TimeInterval {
        guard let began else { return 0 }
        return max(0,(pausedAt ?? date).timeIntervalSince(began)-pausedDuration)
    }
}


enum MeetingFilter: String, CaseIterable, Identifiable {
    case all = "全部会议", complete = "已总结", pending = "待总结"
    var id: String { rawValue }
    func includes(_ meeting: Meeting) -> Bool {
        switch self {
        case .all: return true
        case .complete: return meeting.summaryState == "complete"
        case .pending: return meeting.summaryState != "complete"
        }
    }
}
struct MeetingGroup: Identifiable {
    let id: String
    let meetings: [Meeting]
}
extension Meeting {
    func matchesSearch(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let fields = [title,notes,context] + lines.flatMap { [$0.text,$0.speaker] } + Array((voiceNames ?? [:]).values)
        return terms.allSatisfy { term in fields.contains { $0.localizedCaseInsensitiveContains(term) } }
    }
}
