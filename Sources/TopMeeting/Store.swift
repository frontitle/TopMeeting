import SwiftUI
import AppKit
import AVFoundation

@MainActor final class MeetingStore: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var selected: UUID?
    @Published var recording = false
    @Published var recordingPaused = false
    @Published var inputLevels: [Double] = Array(repeating:-90,count:28)
    @Published var starting = false
    @Published var ending = false
    private var awaitingFinalVoice: UUID?
    @Published var inputLevel: Double = -90
    @Published var liveCaption = ""
    @Published var captureStatus = ""
    @Published var microphones = AudioDevices.inputs()
    @Published var microphoneID: UInt32 = UInt32(UserDefaults.standard.integer(forKey:"microphoneID"))
    @Published var recognitionGain: Double = UserDefaults.standard.object(forKey:"recognitionGain") as? Double ?? 3
    @Published var showingTrash = false
    @Published var search = ""
    @Published var meetingFilter: MeetingFilter = .all
    @Published var elapsed: TimeInterval = 0
    @Published var busy = false
    @Published var connectionChecked = false
    @Published var checking = false
    @Published var streaming = ""
    @Published var chatBusy = false
    @Published var chatStreaming = ""
    @Published var voiceReady = false
    @Published var voiceStatus = "声纹引擎准备中"
    @Published var voiceProfiles: [VoiceProfile] = []
    @Published var identityBusy = false
    @Published var replayingVoices = false
    private var audition: AVAudioPlayer?
    private var auditionTimer: Timer?
    @Published var identityMessage = ""
    private let voice = VoiceRuntime()
    private var pendingManualPerson: (UUID,UUID)?
    private var voiceSessions: [String:(UUID,Double)] = [:]
    @Published var rememberedPeople: [VoiceProfile] = []
    @Published var savedTerms: [TermCorrection] = []
    @Published var correctionStatus = ""
    @Published var documentLabels = UserDefaults.standard.dictionary(forKey:"documentLabels") as? [String:String] ?? [:]
    @Published var documentAutomatic = UserDefaults.standard.dictionary(forKey:"documentAutomatic") as? [String:Bool] ?? [:]
    @Published var documentPending = Set<String>()
    @Published var settingsTab = "general"
    @Published var feishuReady = false
    @Published var feishuChecking = false
    @Published var feishuStatus = "飞书尚未连接"
    @Published var feishuLoginURL: URL?
    var feishuDeviceCode: String?
    @Published var feishuBusy: Set<UUID> = []
    @Published var feishuAutoSync = UserDefaults.standard.bool(forKey:"feishuAutoSync")
    @Published var feishuUploadAudio = UserDefaults.standard.object(forKey:"feishuUploadAudio") as? Bool ?? true
    var feishuClient: any DocumentConnector = FeishuCLI()
    var summaryProvider: any SummaryProvider = ChatCompletionsProvider()
    @Published var providerKind = SummaryProviderKind(rawValue:UserDefaults.standard.string(forKey:"summaryProvider") ?? "openclaw") ?? .openClaw
    @Published var speechLocale = UserDefaults.standard.string(forKey:"speechLocale") ?? "zh-CN"
    @Published var summaryLanguage = UserDefaults.standard.string(forKey:"summaryLanguage") ?? "zh-Hans"
    @Published var interfaceLanguage = UserDefaults.standard.string(forKey:"interfaceLanguage") ?? "zh-Hans"
    @Published var speechLocales: [String] = []
    @Published var notice: String?
    @Published var base = UserDefaults.standard.string(forKey:"gateway") ?? ""
    @Published var agent = UserDefaults.standard.string(forKey:"agent") ?? "openclaw/default"
    @Published var token = ""
    private let capture = SpeechCapture()
    private var timer: Timer?
    private var recordingClock = RecordingClock()
    private var offset: TimeInterval = 0
    private var chatTask: Task<Void, Never>?
    private var summaryTasks: [UUID: Task<Void,Never>] = [:]
    private var summaryRuns: [UUID: UUID] = [:]
    private var summaryInputs: [UUID: String] = [:]
    private var revision = 0
    let directory: URL
    var visibleMeetings: [Meeting] {
        meetings.filter { ($0.deletedAt != nil) == showingTrash && (showingTrash || meetingFilter.includes($0)) && $0.matchesSearch(search) }.sorted { $0.date > $1.date }
    }
    var meetingGroups: [MeetingGroup] {
        let calendar = Calendar.current
        let week = calendar.date(byAdding:.day,value:-7,to:calendar.startOfDay(for:Date())) ?? Date()
        let groups = Dictionary(grouping:visibleMeetings) { m in
            calendar.isDateInToday(m.date) ? "今天" : (m.date >= week ? "近 7 天" : "更早")
        }
        return ["今天","近 7 天","更早"].compactMap { title in groups[title].map { MeetingGroup(id:title,meetings:$0) } }
    }
    var listeningSpeaker: String {
        guard recording, !recordingPaused, voiceReady else { return "识别说话人…" }
        return current?.listeningSpeaker(at:elapsed) ?? "识别说话人…"
    }
    var current: Meeting? { meetings.first { $0.id == selected } }
    init(root: URL? = nil) {
        directory = root ?? FileManager.default.urls(for:.applicationSupportDirectory, in:.userDomainMask)[0].appendingPathComponent("TopMeeting")
        if root == nil {
            base = UserDefaults.standard.string(forKey:providerKind.baseKey) ?? ""
            agent = UserDefaults.standard.string(forKey:providerKind.modelKey) ?? (providerKind == .openClaw ? "openclaw/main" : "")
            token = Vault.read(account:providerKind.credentialAccount)
            Task { speechLocales = await SpeechCapture.supportedLocales() }
        }
        do {
            try FileManager.default.createDirectory(at:directory, withIntermediateDirectories:true)
            let url = directory.appendingPathComponent("meetings.json")
            if FileManager.default.fileExists(atPath:url.path) { meetings = try JSONDecoder().decode([Meeting].self, from:Data(contentsOf:url)) }
        } catch { notice = "会议资料读取失败：\(error.localizedDescription)" }
        for i in meetings.indices {
            for j in meetings[i].lines.indices { meetings[i].lines[j].live = false }
            if meetings[i].summaryState == "generating" { meetings[i].summaryState = "retry" }
            if var messages = meetings[i].messages {
                for j in messages.indices where messages[j].state == "pending" { messages[j].state = "failed"; messages[j].text = "回复中断，可重新发送问题。" }
                meetings[i].messages = messages
            }
        }
        if let data = try? Data(contentsOf:directory.appendingPathComponent("recognition-terms.json")), let terms = try? JSONDecoder().decode([TermCorrection].self,from:data) { savedTerms = terms }
        if let data = try? Data(contentsOf:directory.appendingPathComponent("people.json")), let people = try? JSONDecoder().decode([VoiceProfile].self,from:data) { rememberedPeople = people }
        selected = meetings.first(where:{$0.deletedAt == nil})?.id
        capture.onText = { [weak self] id,text,final,time in
            guard let self, self.recording else { return }
            if !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { self.liveCaption = text }
            self.update { $0.acceptSpeech(id:id,text:text,final:final,time:self.offset + time) }
        }
        capture.onWords = { [weak self] id,words in
            guard let self, self.recording else { return }
            self.update { m in
                if let i = m.lines.firstIndex(where:{$0.id == id}) {
                    m.lines[i].words = words.map { SpeechWord(text:$0.text,start:$0.start + self.offset,end:$0.end + self.offset) }
                }
            }
        }
        voice.onPacket = { [weak self] in self?.handleVoice($0) }
        voice.onFailure = { [weak self] message in self?.voiceReady = false; self?.identityBusy = false; self?.replayingVoices = false; self?.voiceStatus = message }
        capture.onAudio = { [weak voice] data,rate in voice?.audio(data,rate:rate) }
        if root == nil {
            do { try voice.start(profiles:directory.appendingPathComponent("voice-profiles.json")) }
            catch { voiceStatus = error.localizedDescription }
        }
        capture.onLevel = { [weak self] level in
            guard let self else { return }
            self.inputLevel = level
            self.inputLevels = Array((self.inputLevels + [level]).suffix(28))
        }
        capture.onStatus = { [weak self] in self?.captureStatus = $0 }
    }
    private func handleVoice(_ packet: VoicePacket) {
        let previousProfileIDs = Set(voiceProfiles.map(\.id))
        if let profiles = packet.profiles { voiceProfiles = profiles }
        switch packet.type {
        case "ready": voiceReady = true; voiceStatus = "本地声纹匹配与重叠检测已就绪"
        case "turns":
            voiceReady = true
            guard let session = packet.sessionID, let (meetingID,offset) = voiceSessions[session],
                  let i = meetings.firstIndex(where:{$0.id == meetingID}), let events = packet.events else { return }
            if let mappings = packet.mappings { meetings[i].voiceAliases = mappings }
            if let names = packet.names { meetings[i].voiceNames = (meetings[i].voiceNames ?? [:]).filter { $0.key.hasPrefix("name:") }.merging(names) { _,new in new } }
            let aligned = events.map { event -> VoiceTurn in var e = event; e.start += offset; e.end += offset; return e }
            meetings[i].replaceVoiceTurns(aligned,from:(packet.replaceFrom ?? 0) + offset); save()
            if packet.requestID == "final-flush", awaitingFinalVoice == meetingID { finishAfterVoice() }
            if selected == meetingID {
                let recent = aligned.last
                voiceStatus = recent?.overlap == true ? "检测到多人重叠发言 · 混合语音不强行归属" : "最近发言：\(recent?.speakers.joined(separator:" + ") ?? "等待人声")"
            }
        case "replayed":
            replayingVoices = false; voiceStatus = "已有录音分析完成，可试听、标记或合并说话人。"
        case "contact":
            identityBusy = false
            if let (meetingID,lineID) = pendingManualPerson, let mi = meetings.firstIndex(where:{$0.id == meetingID}), let li = meetings[mi].lines.firstIndex(where:{$0.id == lineID}), let personID = packet.personID, let name = packet.personName {
                meetings[mi].lines[li].speaker = name; meetings[mi].lines[li].personID = personID
                var names = meetings[mi].voiceNames ?? [:]; names[personID] = name; meetings[mi].voiceNames = names
                save(); syncRecognitionTerms()
            }
            pendingManualPerson = nil
            identityMessage = "人员已新建。此旧句没有声纹对齐，待后续确认单人声音后完善声纹。"
        case "identity":
            identityBusy = false
            guard let key = packet.meetingID, let id = UUID(uuidString:key), let index = meetings.firstIndex(where:{$0.id == id}) else { return }
            let mappings = packet.mappings ?? [:]
            let restored = Set(voiceProfiles.map(\.id))
            let globalMappings = packet.localOnly == true ? [:] : mappings.filter { previousProfileIDs.contains($0.key) }
            for i in meetings.indices {
                var aliases = meetings[i].voiceAliases ?? [:]
                for identity in restored { aliases.removeValue(forKey:identity) }
                for (source,target) in globalMappings { aliases[source] = target }
                meetings[i].voiceAliases = aliases
                meetings[i].voiceNames = (meetings[i].voiceNames ?? [:]).merging(packet.names ?? [:]) { _,new in new }
            }
            meetings[index].voiceNames = packet.names
            meetings[index].voiceAliases = mappings
            meetings[index].canUndoIdentity = packet.canUndo
            save()
            let learned = packet.learned ?? 0, excluded = packet.quarantined ?? 0
            identityMessage = packet.undone == true ? "已撤销上次标记或合并，声纹样本也已恢复。" : "身份已统一，已吸收 \(learned) 份可靠样本。\(excluded > 0 ? "另有 \(excluded) 份异常样本被隔离，未用于学习。" : "后续可靠发言将继续完善声纹。")"
            syncRecognitionTerms()
            voiceStatus = identityMessage
        case "error":
            if packet.requestID == "identity" { identityBusy = false; identityMessage = packet.message ?? "身份更新失败。" }
            else { replayingVoices = false; voiceStatus = packet.message ?? "声纹分析失败。" }
        default: break
        }
    }
    private func finishAfterVoice() {
        let meetingID = awaitingFinalVoice
        awaitingFinalVoice = nil; ending = false
        if selected == meetingID { analyze(final:true) }
    }
    var discoveredSpeakers: [VoiceProfile] {
        guard let meeting = current else { return [] }
        var speakers: [String:VoiceProfile] = [:]
        for turn in meeting.voiceTurns ?? [] {
            let identity = meeting.namesFor(turn)
            for id in identity.ids where id != "unknown" {
                let idx = turn.speakerIDs.firstIndex(of:id) ?? 0
                let name = meeting.voiceNames?[id] ?? (turn.speakers.indices.contains(idx) ? turn.speakers[idx] : "未标记")
                let old = speakers[id]?.seconds ?? 0
                speakers[id] = VoiceProfile(id:id,name:name,seconds:old + (turn.overlap ? 0 : turn.end-turn.start))
            }
        }
        return speakers.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var meetingSpeakers: [VoiceProfile] {
        var people = discoveredSpeakers
        guard let meeting = current else { return people }
        for line in meeting.lines where !["未标记","unknown",""].contains(line.speaker) {
            let id = line.personID.map { meeting.resolvedSpeaker($0) } ?? "manual:"+line.id.uuidString
            guard !people.contains(where:{ $0.id == id || $0.name == line.speaker }) else { continue }
            people.append(VoiceProfile(id:id,name:meeting.voiceNames?[id] ?? line.speaker,seconds:0))
        }
        return people.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    /// Include human labels from saved transcripts even before the voice engine is ready.
    var allPeople: [VoiceProfile] {
        var result = voiceProfiles
        for person in discoveredSpeakers where !result.contains(where: { $0.id == person.id }) { result.append(person) }
        let ordered = current.map { [$0] } ?? []
        for meeting in ordered + meetings.filter({ $0.id != selected && $0.deletedAt == nil }) {
            for (id,name) in (meeting.voiceNames ?? [:]).sorted(by: { $0.key < $1.key }) {
                let resolved = meeting.resolvedSpeaker(id)
                guard resolved == id, !result.contains(where: { $0.id == resolved || $0.name == name }) else { continue }
                result.append(VoiceProfile(id:resolved,name:name,seconds:0))
            }
            for line in meeting.lines where !["未标记","", "unknown"].contains(line.speaker) {
                guard !result.contains(where: { $0.name == line.speaker }) else { continue }
                result.append(VoiceProfile(id:line.personID ?? "name:" + line.speaker,name:line.speaker,seconds:0))
            }
        }
        for person in rememberedPeople where !result.contains(where: { $0.id == person.id || $0.name == person.name }) { result.append(person) }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func chooseSpeaker(source: String,person: VoiceProfile) {
        if source == person.id { return }
        if source.hasPrefix("manual:"), let lineID = UUID(uuidString:String(source.dropFirst(7))) {
            update { m in
                if let i = m.lines.firstIndex(where: { $0.id == lineID }) { m.lines[i].speaker = person.name; m.lines[i].personID = person.id }
                var names = m.voiceNames ?? [:]; names[person.id] = person.name; m.voiceNames = names
            }
            identityMessage = "已选择「\(person.name)」，已保留在人员列表中。"
            syncRecognitionTerms(); return
        }
        if person.id.hasPrefix("name:") { markSpeaker(source:source,name:person.name) }
        else { markSpeaker(source:source,name:"",target:person.id) }
    }
    func analyzeRecordedVoices() {
        guard voiceReady, !recording, !starting, !ending, !replayingVoices, let meeting = current else { return }
        let paths = meeting.audioSegments ?? meeting.audioPath.map { [$0] } ?? []
        guard !paths.isEmpty else { return }
        let session = UUID().uuidString
        voiceSessions[session] = (meeting.id,0); replayingVoices = true
        voiceStatus = "正在从已有录音发现不同声音，原文和原音保持不变…"
        voice.command(["command":"replay","meetingID":meeting.id.uuidString,"sessionID":session,"paths":paths,"rebuild":true])
    }
    func auditionSpeaker(_ identity: String) {
        guard let meeting = current,
              let turn = (meeting.voiceTurns ?? []).filter({!$0.overlap && meeting.namesFor($0).ids.contains(identity) && $0.end-$0.start >= 0.8}).max(by:{$0.end-$0.start < $1.end-$1.start}) else { return }
        let paths = meeting.audioSegments ?? meeting.audioPath.map { [$0] } ?? []
        var offset: Double = 0
        do {
            for path in paths {
                let url = URL(fileURLWithPath:path)
                let file = try AVAudioFile(forReading:url)
                let duration = Double(file.length)/file.processingFormat.sampleRate
                if turn.start < offset+duration {
                    audition?.stop(); auditionTimer?.invalidate()
                    audition = try AVAudioPlayer(contentsOf:url)
                    audition?.currentTime = max(0,turn.start-offset)
                    audition?.play()
                    auditionTimer = Timer.scheduledTimer(withTimeInterval:min(4,turn.end-turn.start,duration-(turn.start-offset)),repeats:false) { [weak self] _ in Task { @MainActor in self?.audition?.stop() } }
                    return
                }
                offset += duration
            }
        } catch { voiceStatus = "无法试听该声音：\(error.localizedDescription)" }
    }
    func renameInlineSpeaker(_ identity: String,name: String) {
        let name = name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, current?.deletedAt == nil else { return }
        if identity.hasPrefix("manual:"), let id = UUID(uuidString:String(identity.dropFirst(7))) {
            update { m in if let i = m.lines.firstIndex(where:{$0.id == id}) { m.lines[i].speaker = name; m.lines[i].personID = nil } }
            syncRecognitionTerms()
            identityMessage = "已修改本段姓名，未改动声纹。"
        } else { markSpeaker(source:identity,name:name) }
    }
    func createPersonFromSpeaker(_ speakerID: String,name: String) {
        guard voiceReady, !identityBusy, let meeting = current else { return }
        if speakerID.hasPrefix("manual:"), let lineID = UUID(uuidString:String(speakerID.dropFirst(7))) {
            pendingManualPerson = (meeting.id,lineID); identityBusy = true
            voice.command(["command":"contact","name":name,"meetingID":meeting.id.uuidString,"requestID":"identity"])
            return
        }
        let rawID = (meeting.voiceTurns ?? []).reversed().flatMap { $0.sourceIDs ?? $0.speakerIDs }.first { meeting.resolvedSpeaker($0) == speakerID } ?? speakerID
        identityBusy = true; identityMessage = "正在新建人员并建立本场声纹…"
        voice.command(["command":"label","source":rawID,"name":name,"meetingID":meeting.id.uuidString,"requestID":"identity","newPerson":true])
    }
    func markSpeaker(source: String,name: String,target: String? = nil) {
        guard voiceReady, !identityBusy, let id = selected else { return }
        if source.hasPrefix("manual:"), let lineID = UUID(uuidString:String(source.dropFirst(7))), let target {
            let person = (discoveredSpeakers + voiceProfiles).first { $0.id == target }
            if let person {
                update { m in if let i = m.lines.firstIndex(where:{$0.id == lineID}) { m.lines[i].speaker = person.name; m.lines[i].personID = target }; var names = m.voiceNames ?? [:]; names[target] = person.name; m.voiceNames = names }
                identityMessage = "已标记本段姓名，未使用缺少对齐的旧录音训练声纹。"
            }
            return
        }
        identityBusy = true; identityMessage = "正在统一身份并筛选可学习的声纹样本…"
        var command: [String:Any] = ["command":"label","source":source,"name":name,"meetingID":id.uuidString,"requestID":"identity"]
        if let target, !target.isEmpty { command["target"] = target }
        voice.command(command)
    }
    func undoSpeakerIdentity() {
        guard voiceReady, !identityBusy, let id = selected else { return }
        identityBusy = true
        voice.command(["command":"undo","meetingID":id.uuidString,"requestID":"identity"])
    }
    var activeRecognitionTerms: [String] {
        recognitionTerms(savedTerms + (current?.corrections ?? []),names:allPeople.map(\.name))
    }
    private func syncRecognitionTerms() { capture.setContextualTerms(activeRecognitionTerms) }
    func correctWord(lineID: UUID,expected: String,range: NSRange,replacement: String,remember: Bool) throws {
        guard let mi = meetings.firstIndex(where:{$0.id == selected}), meetings[mi].deletedAt == nil,
              let li = meetings[mi].lines.firstIndex(where:{$0.id == lineID}) else { throw Gateway.error("这段实录已不可编辑。") }
        let old = try meetings[mi].lines[li].replaceSelection(range,with:replacement,expected:expected)
        guard old != replacement else { return }
        let correction = TermCorrection(heard:old,preferred:replacement)
        meetings[mi].corrections = (meetings[mi].corrections ?? []) + [correction]
        if remember {
            savedTerms.removeAll { $0.heard == old }; savedTerms.append(correction)
            savedTerms = Array(savedTerms.suffix(300))
            do { try JSONEncoder().encode(savedTerms).write(to:directory.appendingPathComponent("recognition-terms.json"),options:.atomic) }
            catch { notice = "文字已纠正，但常用术语保存失败：\(error.localizedDescription)" }
        }
        syncRecognitionTerms(); save()
        correctionStatus = "已纠正「\(old)」为「\(replacement)」· 后续识别将参考\(remember ? "常用术语" : "本场术语")"
    }
    func update(_ change: (inout Meeting) -> Void) {
        guard let index = meetings.firstIndex(where:{$0.id == selected}) else { return }
        change(&meetings[index]); revision += 1; save()
    }
    func save() {
        let roster = allPeople.filter { !$0.id.hasPrefix("guest") && !$0.name.hasPrefix("说话人 ") && $0.name != "未标记" }
        rememberedPeople = roster
        do {
            try JSONEncoder().encode(roster).write(to:directory.appendingPathComponent("people.json"),options:.atomic)
            try JSONEncoder().encode(meetings).write(to:directory.appendingPathComponent("meetings.json"), options:.atomic) }
        catch { notice = "保存失败：\(error.localizedDescription)" }
    }
    func create() {
        guard !recording && !starting && !ending && !replayingVoices else { return }
        busy = false; streaming = ""
        chatBusy = false; chatStreaming = ""
        showingTrash = false; search = ""
        var m = Meeting(); m.summaryLanguage = summaryLanguage; meetings.insert(m, at:0); selected = m.id; elapsed = 0; save()
    }
    func probe() {
        checking = true; connectionChecked = false
        let testedBase = base, testedToken = token, testedAgent = agent
        Task {
            defer { checking = false }
            do {
                let result = try await Gateway.probe(base:testedBase,token:testedToken,agent:testedAgent)
                guard base == testedBase, token == testedToken, agent == testedAgent else { notice = "连接配置已修改，请重新测试。"; return }
                connectionChecked = true
                notice = result == .catalog ? "Gateway 认证与模型目录连接正常。模型推理仍需通过生成纪要验证。" : "Gateway 认证与对话 HTTP 接口已确认。模型推理仍需通过生成纪要验证。"
            } catch { notice = error.localizedDescription }
        }
    }
    var summaryConnection: SummaryConnection { SummaryConnection(kind:providerKind,base:base,token:token,model:agent) }
    func selectProvider(_ kind: SummaryProviderKind) {
        guard kind != providerKind, !busy, !chatBusy, !checking else { return }
        // Preserve the current configuration before changing extension.
        do { try Vault.save(token,account:providerKind.credentialAccount) }
        catch { notice = error.localizedDescription; return }
        UserDefaults.standard.set(base,forKey:providerKind.baseKey); UserDefaults.standard.set(agent,forKey:providerKind.modelKey)
        providerKind = kind; UserDefaults.standard.set(kind.rawValue,forKey:"summaryProvider")
        base = UserDefaults.standard.string(forKey:kind.baseKey) ?? ""
        agent = UserDefaults.standard.string(forKey:kind.modelKey) ?? (kind == .openClaw ? "openclaw/main" : "")
        token = Vault.read(account:kind.credentialAccount); connectionChecked = false
    }
    func saveSettings() {
        do {
            connectionChecked = false; _ = try Gateway.endpoint(base)
            try Vault.save(token,account:providerKind.credentialAccount)
            UserDefaults.standard.set(base,forKey:providerKind.baseKey); UserDefaults.standard.set(agent,forKey:providerKind.modelKey)
            UserDefaults.standard.set(recognitionGain,forKey:"recognitionGain")
            notice = "连接配置已保存，令牌存放于系统钥匙串。"
        } catch { notice = error.localizedDescription }
    }
    func saveLanguageSettings() {
        UserDefaults.standard.set(interfaceLanguage,forKey:"interfaceLanguage")
        UserDefaults.standard.set([interfaceLanguage],forKey:"AppleLanguages")
        UserDefaults.standard.set(speechLocale,forKey:"speechLocale")
        UserDefaults.standard.set(summaryLanguage,forKey:"summaryLanguage")
        if !recording { update { $0.summaryLanguage = summaryLanguage } }
    }
    func toggleRecordingPause() {
        guard recording, !starting, !ending else { return }
        if recordingPaused {
            do { try capture.resume(); recordingClock.resume(); recordingPaused = false }
            catch { notice = "无法继续录音：\(error.localizedDescription)" }
        } else if capture.pause() {
            recordingClock.pause(); elapsed = offset + recordingClock.elapsed()
            recordingPaused = true; inputLevel = -90; inputLevels = Array(repeating:-90,count:28)
            update { $0.duration = elapsed }
        }
    }
    func toggleRecording() {
        if recording {
            guard !ending else { return }
            ending = true; timer?.invalidate(); update { $0.duration = elapsed }
            Task { [self] in
                // Keep accepting final recognizer results until it has drained.
                await capture.stop()
                recording = false; recordingPaused = false; inputLevel = -90; captureStatus = "录音已结束"
                if voice.isRunning {
                    awaitingFinalVoice = selected; voice.flush()
                    try? await Task.sleep(nanoseconds:3_000_000_000)
                    if ending { finishAfterVoice() }
                } else { ending = false; analyze(final:true) }
            }
            return
        }
        guard !replayingVoices else { return }
        audition?.stop()
        if current == nil { create() }
        guard current?.deletedAt == nil else { return }
        guard !starting, let id = selected else { return }
        starting = true
        liveCaption = ""
        UserDefaults.standard.set(recognitionGain,forKey:"recognitionGain")
        UserDefaults.standard.set(Int(microphoneID),forKey:"microphoneID")
        let url = directory.appendingPathComponent("\(id)-\(UUID()).caf")
        Task { [self] in
            defer { starting = false }
            do {
                offset = current?.duration ?? 0
                if voice.isRunning {
                    let session = UUID().uuidString
                    voiceSessions[session] = (id,offset); voice.session(session,meetingID:id.uuidString,offset:offset)
                }
                syncRecognitionTerms()
                try await capture.start(url:url,gain:Float(recognitionGain),device:microphoneID,localeIdentifier:speechLocale)
                offset = current?.duration ?? 0; recordingClock.start(); recordingPaused = false; inputLevels = Array(repeating:-90,count:28); elapsed = offset; recording = true
                update { $0.summaryState = "live"; $0.audioPath = url.path; $0.audioSegments = ($0.audioSegments ?? []) + [url.path] }
                if let id = selected { startDocumentLinks(id:id) }
                if feishuAutoSync, let id = selected {
                    Task {
                        do { feishuReady = try await feishuClient.status()
                            if feishuReady { await performFeishuSync(id:id,final:false) }
                            else { feishuStatus = "请先登录已绑定的飞书应用" }
                        } catch { feishuStatus = error.localizedDescription }
                    }
                }
                timer = Timer.scheduledTimer(withTimeInterval:1, repeats:true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, !self.recordingPaused else { return }
                        self.elapsed = self.offset + self.recordingClock.elapsed()
                        if Int(self.elapsed) % 15 == 0 { self.update { $0.duration = self.elapsed } }
                        if Int(self.elapsed) % 60 == 0, self.feishuAutoSync, self.feishuReady { self.syncFeishu(final:false) }
                    }
                }
            } catch { notice = error.localizedDescription }
        }
    }
    func trash(_ id: UUID) {
        guard !recording && !starting && !ending && !replayingVoices else { return }
        busy = false; streaming = ""
        guard let i = meetings.firstIndex(where:{$0.id == id}) else { return }
        summaryTasks[id]?.cancel(); summaryRuns[id] = nil; summaryInputs[id] = nil; summaryTasks[id] = nil
        meetings[i].deletedAt = Date()
        if selected == id { selected = visibleMeetings.first?.id }
        save()
    }
    func restore(_ id: UUID) {
        guard let i = meetings.firstIndex(where:{$0.id == id}) else { return }
        meetings[i].deletedAt = nil; save()
        showingTrash = false; selected = id
    }
    func showTrash(_ value: Bool) {
        guard !recording && !starting && !ending && !replayingVoices else { return }
        busy = false; streaming = ""
        showingTrash = value; selected = visibleMeetings.first?.id
    }
    func deleteLine(_ id: UUID) {
        busy = false; streaming = ""
        update { $0.lines.removeAll { $0.id == id } }
    }
    func renameSpeaker(from old: String,to name: String) {
        let clean = name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        update { m in for i in m.lines.indices where m.lines[i].speaker == old { m.lines[i].speaker = clean } }
    }
    func add(_ text: String, speaker: String) {
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        if current == nil { create() }
        guard current?.deletedAt == nil else { return }
        update { $0.lines.append(Line(time:elapsed, speaker:speaker, text:text)) }
    }
    func correct(id: UUID, text: String, speaker: String) {
        update { meeting in
            guard let i = meeting.lines.firstIndex(where:{$0.id == id}) else { return }
            if meeting.lines[i].text != text { meeting.lines[i].original = meeting.lines[i].original ?? meeting.lines[i].text }
            if meeting.lines[i].speaker != speaker { meeting.lines[i].personID = nil }
            meeting.lines[i].text = text; meeting.lines[i].speaker = speaker
        }
    }
    func sendChat(_ text: String) {
        let clean = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty, !chatBusy, let meeting = current, meeting.deletedAt == nil else { return }
        guard !base.isEmpty, !token.isEmpty else { notice = "请先在连接设置中填写 OpenClaw 地址和令牌，再与会议助手对话。"; return }
        let reply = ChatMessage(role:"assistant",text:"",state:"pending")
        update { $0.messages = $0.conversation + [ChatMessage(role:"user",text:clean),reply] }
        guard let snapshot = current else { return }
        chatBusy = true; chatStreaming = ""
        let connection = summaryConnection, provider = summaryProvider
        chatTask = Task {
            do {
                var result = ""
                try await provider.stream(connection:connection,meeting:snapshot,mode:.conversation) { chunk in
                    result += chunk
                    if self.selected == snapshot.id { self.chatStreaming = result }
                }
                try Task.checkCancellation()
                guard !result.isEmpty else { throw Gateway.error("会议助手未返回内容，请重试。") }
                finishChat(meetingID:snapshot.id,messageID:reply.id,text:result,state:"complete")
            } catch {
                finishChat(meetingID:snapshot.id,messageID:reply.id,text:Task.isCancelled ? "回复已取消，可重新发送。" : error.localizedDescription,state:"failed")
            }
        }
    }
    func retryChat() {
        guard !chatBusy, let m = current, m.conversation.count >= 2,
              m.conversation.last?.state == "failed", m.conversation[m.conversation.count - 2].role == "user" else { return }
        guard !base.isEmpty, !token.isEmpty else { notice = "请先配置 OpenClaw 连接。"; return }
        let question = m.conversation[m.conversation.count - 2].text
        update { $0.messages = Array($0.conversation.dropLast(2)) }
        sendChat(question)
    }
    private func finishChat(meetingID: UUID,messageID: UUID,text: String,state: String) {
        guard let i = meetings.firstIndex(where:{$0.id == meetingID}), var messages = meetings[i].messages,
              let j = messages.firstIndex(where:{$0.id == messageID}) else { return }
        messages[j].text = text; messages[j].state = state; meetings[i].messages = messages; save()
        if selected == meetingID { chatBusy = false; chatStreaming = "" }
    }
    func analyze(final: Bool = false) {
        guard var meeting = current, meeting.deletedAt == nil, !meeting.lines.isEmpty else { return }
        meeting.lines = meeting.lines.filter { $0.live != true }
        guard !meeting.lines.isEmpty else { return }
        let isFinal = final || !recording
        guard !base.isEmpty, !token.isEmpty else {
            if isFinal { update { $0.summaryState = "connection" }; if feishuAutoSync && feishuReady { syncFeishu(final:true) } }
            else { notice = "请先配置 OpenClaw 连接。" }
            return
        }
        let fingerprint = Gateway.notesSignature(meeting:meeting,final:isFinal) + ":" + summaryConnection.cacheKey
        guard summaryInputs[meeting.id] != fingerprint else { return }
        if meeting.summaryFingerprint == fingerprint && !meeting.notes.isEmpty {
            if isFinal {
                update { $0.summaryState = "complete" }
                if feishuAutoSync && feishuReady { syncFeishu(final:true) }
            }
            return
        }
        summaryInputs[meeting.id] = fingerprint
        summaryTasks[meeting.id]?.cancel()
        let run = UUID(); summaryRuns[meeting.id] = run
        busy = true; streaming = ""
        update { $0.summaryState = "generating" }
        let capturedLines = meeting.lines
        let connection = summaryConnection, provider = summaryProvider
        summaryTasks[meeting.id] = Task {
            defer { if summaryRuns[meeting.id] == run { summaryInputs[meeting.id] = nil; summaryTasks[meeting.id] = nil } }
            do {
                var result = ""
                try await provider.stream(connection:connection,meeting:meeting,mode:.notes(final:isFinal)) { chunk in
                    result += chunk
                    if self.selected == meeting.id, self.summaryRuns[meeting.id] == run { self.streaming = result }
                }
                try Task.checkCancellation()
                guard summaryRuns[meeting.id] == run,
                      let i = meetings.firstIndex(where:{$0.id == meeting.id}), meetings[i].deletedAt == nil else { return }
                let latest = meetings[i]
                guard latest.context == meeting.context, latest.userClarifications == meeting.userClarifications, latest.voiceAliases == meeting.voiceAliases, latest.voiceNames == meeting.voiceNames,
                      Array(latest.lines.filter { $0.live != true }.prefix(capturedLines.count)) == capturedLines else {
                    meetings[i].summaryState = "retry"; save()
                    if selected == meeting.id { busy = false; streaming = "" }; return
                }
                guard !result.isEmpty else { throw Gateway.error("远程未返回纪要内容。") }
                meetings[i].notes = result; meetings[i].summaryState = isFinal ? "complete" : "live"
                meetings[i].summarizedAt = Date(); meetings[i].summaryFingerprint = fingerprint; save()
                if feishuAutoSync && feishuReady { syncFeishu(id:meeting.id,final:isFinal) }
                if selected == meeting.id { busy = false; streaming = "" }
            } catch {
                guard summaryRuns[meeting.id] == run else { return }
                if let i = meetings.firstIndex(where:{$0.id == meeting.id}) { meetings[i].summaryState = "retry"; save() }
                if isFinal && feishuAutoSync && feishuReady { syncFeishu(id:meeting.id,final:true) }
                if selected == meeting.id { busy = false; streaming = "" }
            }
        }
    }
    func select(_ id: UUID) {
        guard !recording && !starting && !ending && !replayingVoices else { return }
        busy = false; streaming = ""; selected = id; elapsed = current?.duration ?? 0; busy = current?.summaryState == "generating"; chatBusy = current?.conversation.contains(where:{$0.state == "pending"}) ?? false; chatStreaming = ""; syncRecognitionTerms()
    }
    func export() {
        guard let m = current else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "\(m.title).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let dialogue = m.conversation.map { "**\($0.role == "user" ? "我" : "AI")**：\($0.text)" }.joined(separator:"\n\n")
        let text = "# \(m.title)\n\n\(m.notes)\n\n## 会议对话与补充\n\(m.context)\n\(dialogue)\n\n## 全文转写\n" + m.lines.map { "[\(clock($0.time))] **\($0.speaker)**：\($0.text)" }.joined(separator:"\n\n")
        do { try text.write(to:url, atomically:true, encoding:.utf8) } catch { notice = error.localizedDescription }
    }
}
