import Foundation
import AVFoundation

actor FeishuMock {
    var calls: [[String]] = []
    var payloads: [String] = []
    var fail = false
    func failNext() { fail = true }
    func count() -> Int { calls.count }
    func respond(_ args: [String],_ input: Data?) throws -> Data {
        calls.append(args)
        if let input { payloads.append(String(decoding:input,as:UTF8.self)) }
        if fail { fail = false; throw Gateway.error("Simulated response lost after sending") }
        if args.contains("+create") { return Data(#"{"ok":true,"data":{"document":{"document_id":"test-doc","url":"https://example.feishu.cn/docx/test-doc"}}}"#.utf8) }
        return Data(#"{"ok":true}"#.utf8)
    }
}

@main struct CoreChecks {
    static func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw NSError(domain:"CoreChecks",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
    }
    @MainActor static func main() async throws {
        let clockStart = Date(timeIntervalSince1970:100)
        var recordingClock = RecordingClock(); recordingClock.start(at:clockStart)
        recordingClock.pause(at:clockStart.addingTimeInterval(10))
        try check(recordingClock.elapsed(at:clockStart.addingTimeInterval(100)) == 10,"Recording time advanced during pause")
        recordingClock.pause(at:clockStart.addingTimeInterval(90))
        recordingClock.resume(at:clockStart.addingTimeInterval(110))
        try check(recordingClock.elapsed(at:clockStart.addingTimeInterval(115)) == 15,"Resume included paused wall time")
        recordingClock.resume(at:clockStart.addingTimeInterval(120))
        recordingClock.pause(at:clockStart.addingTimeInterval(125))
        try check(recordingClock.elapsed(at:clockStart.addingTimeInterval(200)) == 25,"Second pause corrupted audio timeline")
        var gainControl = RecognitionGain()
        var quietGain: Float = 1
        for _ in 0..<50 { quietGain = gainControl.next(level:-48,peak:0.01,base:3,duration:0.05) }
        try check(quietGain > 5.5 && quietGain <= 6,"Distant voice compensation failed")
        let loudGain = gainControl.next(level:-8,peak:0.8,base:3,duration:0.05)
        try check(loudGain * 0.8 <= 0.98001,"Nearby voice clips after quiet speaker")
        for _ in 0..<100 { quietGain = gainControl.next(level:-80,peak:0.0001,base:3,duration:0.05) }
        try check(quietGain < 3.01,"Silence increased automatic gain")
        for base in ["https://meeting.example", "https://meeting.example/", "https://meeting.example/v1", "https://meeting.example/v1/", "https://meeting.example/v1/chat/completions"] {
            let value = try Gateway.endpoint(base).absoluteString
            try check(value == "https://meeting.example/v1/chat/completions","Gateway URL normalization failed")
        }
        for invalid in ["ws://meeting.example", "https://user:secret@meeting.example", "https://meeting.example?token=secret", "invalid"] {
            var rejected = false
            do { _ = try Gateway.endpoint(invalid) } catch { rejected = true }
            try check(rejected,"Unsafe URL accepted")
        }
        try check(!UtteranceBoundary.shouldFinish(hasText:true,age:10,silence:1.2,stable:3),"Brief breath split continuous speech")
        try check(!UtteranceBoundary.shouldFinish(hasText:true,age:3,silence:2.5,stable:2.5),"Short partial phrase ended too early")
        try check(!UtteranceBoundary.shouldFinish(hasText:true,age:12,silence:3,stable:0.5),"Changing caption was cut off")
        try check(UtteranceBoundary.shouldFinish(hasText:true,age:12,silence:2.3,stable:2.1),"Sustained pause never finalized")
        try check(UtteranceBoundary.shouldFinish(hasText:true,age:45,silence:0,stable:0),"Continuous speech never rotated")
        var m = Meeting(); m.context = "金额单位为万元"
        m.lines = [Line(time:12,speaker:"小王",text:"晓艾",original:"小爱")]
        m.audioSegments = ["one.caf","two.caf"]
        let decoded = try JSONDecoder().decode(Meeting.self,from:JSONEncoder().encode(m))
        try check(decoded.lines == m.lines && decoded.context == m.context && decoded.audioSegments == m.audioSegments,"Meeting persistence lost correction or audio segments")
        try check(NoteSection.parse("").isEmpty,"Empty notes produced invented board content")
        let sections = NoteSection.parse("## 决策\n尚未决定\n## 待办\n负责人待确认")
        try check(sections.map(\.title) == ["决策","待办"],"Board headings changed")
        try check(sections.last?.body == "负责人待确认","Board lost uncertainty")
        try check(clock(-1) == "00:00" && clock(3661) == "61:01","Clock formatting failed")
        for interleaved in [false,true] {
            let format = AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:16000,channels:2,interleaved:interleaved)!
            let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:1600)!
            buffer.frameLength = 1600
            let planes = interleaved ? 1 : 2, samples = interleaved ? 3200 : 1600
            for channel in 0..<planes { for frame in 0..<samples { buffer.floatChannelData![channel][frame] = 0.0003 } }
            let before = AudioSamples.level(buffer)
            let enhanced = AudioSamples.amplified(buffer,gain:3)!
            try check(AudioSamples.level(enhanced) > before + 9,"Quiet audio was not enhanced")
            try check(buffer.floatChannelData![0][0] == 0.0003,"Gain modified original recording buffer")
            try check(enhanced.frameLength == buffer.frameLength,"Quiet frames were dropped")
            buffer.floatChannelData![0][0] = 1
            buffer.floatChannelData![0][1] = .nan
            let limited = AudioSamples.amplified(buffer,gain:6)!
            try check(limited.floatChannelData![0][0] <= 0.98 && limited.floatChannelData![0][1] == 0,"Limiter failed")
        }
        let utterance = UUID()
        var live = Meeting()
        live.acceptSpeech(id:utterance,text:"第一位",final:false,time:0)
        live.acceptSpeech(id:utterance,text:"第一位说话人",final:false,time:0)
        live.acceptSpeech(id:utterance,text:"第一位说话人。",final:true,time:0)
        try check(live.lines.count == 1 && live.lines[0].live == false,"Streaming produced duplicate or unfinished rows")
        live.lines[0].original = live.lines[0].text; live.lines[0].text = "人工纠正"
        live.acceptSpeech(id:utterance,text:"迟到的识别结果",final:true,time:0)
        try check(live.lines[0].text == "人工纠正","Late result overwrote manual correction")
        live.acceptSpeech(id:UUID(),text:"另一位较远的发言",final:true,time:3)
        try check(live.lines.count == 2 && live.lines[1].speaker == "未标记","A second utterance was lost or falsely identified")
        var attributed = Meeting()
        let continuous = UUID()
        attributed.lines = [Line(id:continuous,time:0,speaker:"未标记",text:"甲说预算乙说进度",words:[SpeechWord(text:"甲说预算",start:0.5,end:1.5),SpeechWord(text:"乙说进度",start:2.5,end:3.5)])]
        attributed.replaceVoiceTurns([
            VoiceTurn(start:0,end:2,speakers:["甲"],speakerIDs:["a"],confidence:0.84,overlap:false),
            VoiceTurn(start:2,end:4,speakers:["乙"],speakerIDs:["b"],confidence:0.83,overlap:false)
        ],from:0)
        try check(attributed.attributedLines.map(\.speaker) == ["甲","乙"],"Continuous ASR utterance did not split by voice identity")
        try check(attributed.listeningSpeaker(at:1) == "甲","Listening label used a future speaker")
        try check(attributed.listeningSpeaker(at:3) == "乙","Listening label missed current speaker")
        try check(attributed.listeningSpeaker(at:8) == "识别说话人…","Listening label reused stale speaker after silence")
        var namedListening = attributed
        namedListening.voiceAliases = ["b":"named-b"]
        namedListening.voiceNames = ["named-b":"张经理"]
        try check(namedListening.listeningSpeaker(at:3) == "张经理","Listening label ignored renamed canonical identity")
        namedListening.voiceTurns = [VoiceTurn(start:0,end:4,speakers:["未标记"],speakerIDs:["unknown"],confidence:0,overlap:false)]
        try check(namedListening.listeningSpeaker(at:2) == "说话人待确认","Uncertain voice was presented as identified")
        let paragraphID = attributed.transcriptParagraphs.first?.id
        try check(attributed.transcriptParagraphs.count == 1 && attributed.transcriptParagraphs.first?.text == attributed.lines[0].text,"Voice changes fragmented the finalized paragraph")
        try check(attributed.transcriptParagraphs.first?.speakerIDs == ["a","b"],"Whole paragraph lost speaker annotations")
        try check(attributed.transcriptParagraphs.first?.speakerNames == ["a":"甲","b":"乙"],"Paragraph header lost individual names")
        attributed.lines[0].live = true
        try check(attributed.transcriptParagraphs.isEmpty,"Provisional recognition leaked into editable transcript")
        attributed.lines[0].live = false
        attributed.replaceVoiceTurns([VoiceTurn(start:2,end:4,speakers:["甲","乙"],speakerIDs:["a","b"],confidence:0.8,overlap:true)],from:2)
        try check(attributed.listeningSpeaker(at:3).hasPrefix("重叠"),"Listening label lost overlapping voices")
        try check(attributed.attributedLines.last?.overlap == true,"Overlap flag was lost in transcript alignment")
        try check(attributed.transcriptParagraphs.count == 1 && attributed.transcriptParagraphs.first?.id == paragraphID && attributed.transcriptParagraphs.first?.overlap == true,"Later overlap detection changed paragraph boundary or lost warning")
        try check(attributed.voiceTurns?.first?.speakerIDs == ["a"],"Sliding window update erased earlier speaker history")
        attributed.lines[0].speaker = "人工指定"
        try check(attributed.attributedLines.first?.speaker == "人工指定","Voice matching overwrote manual speaker assignment")
        try check(attributed.transcriptParagraphs.first?.speaker == "人工指定","Paragraph annotation overrode manual speaker")
        attributed.lines[0].speaker = "未标记"
        attributed.voiceTurns = [VoiceTurn(start:0,end:4,speakers:["甲"],speakerIDs:["person-a"],confidence:0.84,overlap:false,sourceIDs:["guest-original"])]
        attributed.voiceAliases = ["guest-original":"person-a"]
        attributed.voiceNames = ["person-a":"甲","guest-original":"说话人 2"]
        try check(attributed.attributedLines.first?.speaker == "甲","Quick naming did not update historical transcript")
        attributed.voiceAliases = [:]
        try check(attributed.attributedLines.first?.speaker == "说话人 2","Undo could not recover pre-merge identity provenance")
        let legacyJSON = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"title\":\"旧会议\",\"date\":0,\"lines\":[],\"notes\":\"\",\"context\":\"\",\"duration\":0}".utf8)
        let legacy = try JSONDecoder().decode(Meeting.self,from:legacyJSON)
        try check(legacy.voiceTurns == nil,"Legacy meeting migration failed")
        var repeated = Line(time:0,speaker:"未标记",text:"小爱讨论小爱。",live:false,words:[SpeechWord(text:"小爱",start:0,end:1),SpeechWord(text:"讨论",start:1,end:2),SpeechWord(text:"小爱",start:2,end:3)])
        let originalText = repeated.text
        _ = try repeated.replaceSelection(NSRange(location:4,length:2),with:"晓艾科技",expected:originalText)
        try check(repeated.text == "小爱讨论晓艾科技。" && repeated.original == originalText,"Selected occurrence correction changed another occurrence")
        try check(repeated.words?.last?.text == "晓艾科技" && repeated.words?.last?.start == 2,"Word correction lost timestamp")
        var correctedMeeting = Meeting(); correctedMeeting.lines = [repeated]
        correctedMeeting.voiceTurns = [VoiceTurn(start:0,end:1.8,speakers:["甲"],speakerIDs:["a"],confidence:0.9,overlap:false),VoiceTurn(start:1.8,end:4,speakers:["乙"],speakerIDs:["b"],confidence:0.9,overlap:false)]
        try check(correctedMeeting.attributedLines.map(\.speaker) == ["甲","乙"],"Word correction erased speaker segmentation")
        try check(correctedMeeting.attributedLines.map(\.text).joined() == repeated.text,"Display ranges lost punctuation or corrected words")
        try check(correctedMeeting.transcriptParagraphs.count == 1 && correctedMeeting.transcriptParagraphs.first?.text == repeated.text,"Correction fragmented or truncated paragraph")
        try check(correctedMeeting.transcriptParagraphs.first?.sourceRange == NSRange(location:0,length:(repeated.text as NSString).length),"Paragraph selection no longer addresses full source")
        var rejectedStale = false
        do { _ = try repeated.replaceSelection(NSRange(location:0,length:2),with:"晓艾",expected:originalText) } catch { rejectedStale = true }
        try check(rejectedStale,"Stale text selection was applied")
        var emoji = Line(time:0,speaker:"测试",text:"你好🙂小爱")
        _ = try emoji.replaceSelection(NSRange(location:4,length:2),with:"晓艾",expected:emoji.text)
        try check(emoji.text == "你好🙂晓艾","UTF16 selection corrupted emoji")
        var liveLine = Line(time:0,speaker:"测试",text:"识别中",live:true)
        var rejectedLive = false
        do { _ = try liveLine.replaceSelection(NSRange(location:0,length:2),with:"修改",expected:liveLine.text) } catch { rejectedLive = true }
        try check(rejectedLive,"Unstable live text was modified")
        let termList = (0..<120).map { TermCorrection(heard:"错词\($0)",preferred:"术语\($0)") }
        try check(recognitionTerms(termList).count == 100 && recognitionTerms(termList).first == "术语119","ASR vocabulary order or limit failed")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = MeetingStore(root:root)
        store.create(); let first = store.selected!
        store.add("保留原文",speaker:"测试")
        store.create(); let second = store.selected!
        store.trash(first)
        try check(store.visibleMeetings.count == 1 && store.selected == second,"Deleting another meeting changed selection")
        store.showTrash(true)
        try check(store.visibleMeetings.count == 1 && store.current?.id == first,"Deleted meeting missing from trash")
        store.restore(first)
        try check(store.current?.lines.first?.text == "保留原文" && store.visibleMeetings.count == 2,"Restore lost meeting content")
        store.recording = true; store.trash(first)
        try check(store.current?.deletedAt == nil,"Recording meeting could be deleted")
        store.recording = false; store.trash(first)
        let reloaded = MeetingStore(root:root)
        try check(reloaded.meetings.first(where:{$0.id == first})?.deletedAt != nil,"Trash state did not survive restart")
        store.create()
        store.add("小爱与小爱",speaker:"测试")
        let correctedID = store.current!.lines[0].id
        try store.correctWord(lineID:correctedID,expected:"小爱与小爱",range:NSRange(location:3,length:2),replacement:"晓艾",remember:true)
        try check(store.activeRecognitionTerms.contains("晓艾"),"Corrected term did not reach ASR hints")
        let termReload = MeetingStore(root:root)
        try check(termReload.savedTerms.contains(where:{$0.preferred == "晓艾"}),"ASR vocabulary was not persisted")
        try check(Gateway.prompt(meeting:store.current!,transcript:store.current!.lines[0].text,mode:.notes(final:true)).contains("小爱 → 晓艾"),"Correction did not reach AI meeting context")
        // All previously labelled people are selectable before the acoustic engine starts.
        store.update { $0.lines.append(Line(time:9,speaker:"张老师",text:"测试")) }
        try check(store.allPeople.contains(where: { $0.name == "张老师" }),"Manual speaker missing from shared picker")
        let known = store.allPeople.first { $0.name == "张老师" }!
        let unlabelled = Line(time:10,speaker:"未标记",text:"再发言")
        store.update { $0.lines.append(unlabelled) }
        store.chooseSpeaker(source:"manual:"+unlabelled.id.uuidString,person:known)
        try check(store.current!.lines.last?.speaker == "张老师","Existing manual speaker not reusable without voice engine")
        let peopleReload = MeetingStore(root:root)
        try check(peopleReload.allPeople.contains(where: { $0.name == "张老师" }),"People list did not survive restart")
        let fakeCLI = root.appendingPathComponent("fake-feishu")
        let fakeProgram = """
        #!/usr/bin/env python3
        import json,os,sys
        print(json.dumps({'ok':True,'input':sys.stdin.read() if '--content' in sys.argv else '', 'file_exists':os.path.isfile(sys.argv[sys.argv.index('--file')+1]) if '--file' in sys.argv else False}))
        """
        try Data(fakeProgram.utf8).write(to:fakeCLI)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:fakeCLI.path)
        let nativeCLI = FeishuCLI(executable:fakeCLI)
        let stdinProbe = try FeishuCLI.receipt(await nativeCLI.run(["--content","-"],Data("会议<&>\n第二行".utf8)))
        try check(stdinProbe["input"] as? String == "会议<&>\n第二行","Native CLI stdin lost Unicode or newlines")
        let pathProbe = root.appendingPathComponent("附件 含空格.caf"); try Data([1]).write(to:pathProbe)
        let fileProbe = try FeishuCLI.receipt(await nativeCLI.run(["--file",pathProbe.path],nil))
        try check(fileProbe["file_exists"] as? Bool == true,"CLI relative attachment path failed")
        var missingReceiptRejected = false
        do { _ = try FeishuCLI.receipt(Data("{}".utf8)) } catch { missingReceiptRejected = true }
        try check(missingReceiptRejected,"Missing cloud receipt falsely accepted")
        let identityStore = MeetingStore(root:root.appendingPathComponent("identity-ui"))
        identityStore.create()
        identityStore.update { m in
            m.voiceAliases = ["guest-shadow":"guest-a"]
            m.voiceNames = ["guest-a":"甲","guest-b":"乙","guest-c":"丙"]
            m.voiceTurns = [VoiceTurn(start:0,end:1,speakers:["甲"],speakerIDs:["guest-a"],confidence:0.9,overlap:false),
                            VoiceTurn(start:1,end:2,speakers:["乙"],speakerIDs:["guest-b"],confidence:0.9,overlap:false),
                            VoiceTurn(start:2,end:3,speakers:["丙"],speakerIDs:["guest-c"],confidence:0.9,overlap:false),
                            VoiceTurn(start:3,end:4,speakers:["重复候选"],speakerIDs:["guest-shadow"],confidence:0.9,overlap:false)]
        }
        try check(identityStore.discoveredSpeakers.count == 3,"Canonical duplicate counted as another meeting participant")
        let mock = FeishuMock()
        store.feishuClient = FeishuCLI(run: { try await mock.respond($0,$1) })
        store.feishuReady = true; store.feishuAutoSync = false; store.feishuUploadAudio = true
        let fakeAudio = root.appendingPathComponent("录音 空格.caf"); try Data([1,2,3]).write(to:fakeAudio)
        store.update { $0.notes = "## 已明确决策\n保留原文 <script>&\n## 行动待办\n负责人待确认"; $0.summaryState = "complete"; $0.audioSegments = [fakeAudio.path] }
        let syncID = store.current!.id
        await store.performFeishuSync(id:syncID,final:true)
        try check(store.current!.feishu?.id == "test-doc" && store.current!.feishu?.pending == nil,"Feishu state not persisted")
        try check(store.current!.feishu?.attachments == [fakeAudio.path],"Audio receipt missing")
        let count = await mock.count()
        try check(count == 4,"Expected create, transcript, board and audio")
        await store.performFeishuSync(id:syncID,final:true)
        let afterRepeat = await mock.count()
        try check(afterRepeat == count,"Unchanged sync duplicated cloud content")
        try check(FeishuCLI.content(store.current!,final:true).contains("&lt;script&gt;&amp;"),"Transcript XML not escaped")
        try check(!FeishuCLI.board(Meeting()).contains("whiteboard"),"Empty notes invented board")
        try check(FeishuCLI.safeDocumentURL("https://evil.example/docx/test") == nil,"Untrusted recovery link accepted")
        await mock.failNext()
        store.update { $0.lines.append(Line(time:15,speaker:"张老师",text:"修订后的内容")) }
        await store.performFeishuSync(id:syncID,final:true)
        try check(store.current!.feishu?.pending == "追加会议记录","Uncertain write was falsely acknowledged")
        let failedCount = await mock.count()
        await store.performFeishuSync(id:syncID,final:true)
        let afterBlocked = await mock.count()
        try check(afterBlocked == failedCount,"Uncertain write was automatically resent")
        store.acceptFeishuPending()
        await store.performFeishuSync(id:syncID,final:true)
        let afterConfirmed = await mock.count()
        try check(afterConfirmed == failedCount,"Confirmed write was duplicated")
        let syncReload = MeetingStore(root:root)
        try check(syncReload.current?.feishu?.attachments == [fakeAudio.path],"Cloud receipts lost on restart")
        store.feishuReady = false
        let base = "http://127.0.0.1:19876"
        try await Gateway.probe(base:base,token:"local-test-only")
        let legacyProbe = try await Gateway.probe(base:base+"/legacy",token:"local-test-only")
        try check(legacyProbe == .chatEndpoint,"Chat-only gateway incorrectly rejected")
        for (path,expected) in [("auth","认证失败"),("off","未提供对话 HTTP 接口"),("html","网页")] {
            var message = ""
            do { try await Gateway.probe(base:base+"/"+path,token:"local-test-only") } catch { message = error.localizedDescription }
            try check(message.contains(expected),"Connection error did not distinguish \(path)")
        }
        var result = ""
        try await Gateway.stream(base:base,token:"local-test-only",agent:"openclaw/default",meeting:m) { result += $0 }
        try check(result == "## 决策\n尚未决定","SSE stream did not preserve content")
        var compatibleResult = ""
        try await Gateway.stream(base:base,token:"local-test-only",agent:"compatible-test",meeting:m,provider:.compatible) { compatibleResult += $0 }
        try check(compatibleResult == result,"Compatible model stream failed")
        var englishMeeting = m; englishMeeting.summaryLanguage = "en"
        try check(Gateway.prompt(meeting:englishMeeting,transcript:"晓艾",mode:.notes(final:true)).contains("English"),"English summary instruction missing")
        let connection = SummaryConnection(kind:.compatible,base:base,token:"secret-a",model:"a")
        try check(connection.cacheKey == SummaryConnection(kind:.compatible,base:base,token:"secret-b",model:"a").cacheKey,"Credential leaked into cache identity")
        try check(connection.cacheKey != SummaryConnection(kind:.compatible,base:base,token:"secret-a",model:"b").cacheKey,"Model changes reuse summary identity")
        var searchable = Meeting(); searchable.title = "产品讨论"; searchable.notes = "负责人林悦"
        try check(searchable.matchesSearch("产品 林悦"),"Library search did not combine title and notes")
        try check(!searchable.matchesSearch("产品 不存在"),"Library search ignored a term")
        var rejected = false
        do { try await Gateway.stream(base:base,token:"local-test-only",agent:"fail",meeting:m) { _ in } } catch { rejected = true }
        try check(rejected,"Truncated stream was accepted")
        store.base = base; store.token = "local-test-only"; store.select(second)
        store.update { $0.lines = m.lines }
        store.recording = true
        store.toggleRecording()
        for _ in 0..<150 {
            if store.current?.summaryState == "complete" { break }
            try await Task.sleep(nanoseconds:20_000_000)
        }
        try check(!store.recording && store.current?.summaryState == "complete","Ending meeting did not trigger a final summary")
        let summarizedAt = store.current!.summarizedAt
        store.analyze(final:true)
        try check(!store.busy && store.current!.summarizedAt == summarizedAt,"Unchanged summary was resubmitted")
        let reloadedSummary = MeetingStore(root:root)
        reloadedSummary.select(second); reloadedSummary.base = base; reloadedSummary.token = "local-test-only"
        reloadedSummary.analyze(final:true)
        try check(!reloadedSummary.busy,"Summary deduplication was lost on reload")
        let notesBeforeChat = store.current!.notes
        store.sendChat("这里说的是晓艾，不是小爱")
        for _ in 0..<150 {
            if !store.chatBusy && store.current?.conversation.last?.state == "complete" { break }
            try await Task.sleep(nanoseconds:20_000_000)
        }
        try check(store.current?.conversation.count == 2,"Conversation did not persist both roles")
        try check(store.current?.conversation.last?.text == "已理解，会使用晓艾这一名称。","Chat response used summary mode")
        try check(store.current?.lines == m.lines,"Chat changed spoken transcript")
        try check(!store.busy,"Chat launched a hidden full summary")
        try check(store.current?.notes == notesBeforeChat,"Chat response replaced structured notes")
        let persisted = MeetingStore(root:root)
        try check(persisted.meetings.first(where:{$0.id == second})?.conversation.count == 2,"Chat lost after reload")
        store.analyze(final:true)
        let inFlightState = store.current?.summaryState
        store.analyze(final:true)
        try check(store.current?.summaryState == inFlightState,"Repeated summary changed in-flight request")
        store.create()
        for _ in 0..<150 {
            if store.meetings.first(where:{$0.id == second})?.summaryState == "complete" { break }
            try await Task.sleep(nanoseconds:20_000_000)
        }
        try check(store.meetings.first(where:{$0.id == second})?.summaryState == "complete","Switching meetings cancelled final summary")
        store.token = ""; store.select(second); store.recording = true; store.toggleRecording()
        for _ in 0..<100 { if !store.ending { break }; try await Task.sleep(nanoseconds:20_000_000) }
        try check(store.current?.summaryState == "connection","Missing connection was falsely marked as a successful final summary")
        try check(Gateway.prompt(meeting:m,transcript:"晓艾",mode:.notes(final:true)).contains("会议已经结束"),"Final summary prompt missing whole-meeting instruction")
        try check(Gateway.prompt(meeting:m,transcript:"晓艾",mode:.conversation).contains("最后一条用户消息"),"Conversation prompt was not distinct")
        print("PASS: complete finalized paragraphs, stable rows across voice changes, full-source corrections, persistent summary deduplication, chat without hidden summarization, async recognition drain, reusable historical people, persisted roster, Feishu stage receipts, duplicate prevention, uncertain-write blocking/reconciliation, XML escaping, final-only board, selection-only correction, UTF16/emoji safety, stale/live protection, timestamp retention, persisted ASR vocabulary, AI correction context, acoustic turn/word alignment, overlap UI flags, sliding-window retention, legacy migration, end-of-meeting summary, conversation isolation/persistence, background finalization, missing-connection state, quiet-input gain, raw-buffer preservation, multichannel/interleaved audio, limiter, streaming upsert, manual-correction protection, meeting deletion/restore/reload, recording deletion guard, URL validation, correction persistence, audio segments, board provenance, clock, authenticated probe, SSE streaming, truncated-stream rejection")
    }
}
