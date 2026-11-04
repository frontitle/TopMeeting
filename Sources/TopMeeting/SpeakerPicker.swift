import SwiftUI

/// One field searches saved people and names the current anonymous voice.
struct SpeakerPickerMenu: View {
    @Binding var query: String
    let people: [VoiceProfile]
    let currentID: String
    var busy = false
    var enabled = true
    var footer = "后续将自动应用修改后的名称"
    var canUndo = false
    let select: (VoiceProfile) -> Void
    let add: (String) -> Void
    var undo: () -> Void = {}
    @InlineFocus<Bool> private var focused
    private var clean: String { query.trimmingCharacters(in:.whitespacesAndNewlines) }
    private var matches: [VoiceProfile] {
        people.filter { clean.isEmpty || $0.name.localizedCaseInsensitiveContains(clean) }
    }
    private var exact: [VoiceProfile] { people.filter { $0.name == clean } }
    private var canAdd: Bool { !clean.isEmpty && clean.count <= 60 && exact.isEmpty }
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                TextField(L10n.tr("输入人名"),text:$query).textFieldStyle(.plain).font(.system(size:17))
                    .focused($focused).onSubmit(submit).disabled(busy)
                if busy { ProgressView().controlSize(.small) }
                else if !query.isEmpty {
                    Button { query = ""; focused = true } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help(L10n.tr("清空姓名"))
                }
            }.padding(18)
            Divider()
            if canAdd {
                Button { add(clean) } label: {
                    HStack(spacing:12) {
                        Image(systemName:"person.badge.plus").font(.system(size:19)).frame(width:38,height:38)
                            .background(MeetingStyle.accent.opacity(0.08),in:Circle())
                        Text(L10n.tr("添加 \(clean) 为说话人")).font(.system(size:14,weight:.medium)).lineLimit(2)
                        Spacer(minLength:0)
                    }.foregroundStyle(MeetingStyle.accent).padding(16).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!enabled || busy)
            }
            if !matches.isEmpty {
                ScrollView {
                    LazyVStack(spacing:2) {
                        ForEach(matches) { person in
                            Button { select(person) } label: {
                                HStack(spacing:12) {
                                    Text(String(person.name.prefix(2))).font(.system(size:12,weight:.medium))
                                        .foregroundStyle(MeetingStyle.personColor(person.id)).frame(width:36,height:36)
                                        .background(MeetingStyle.personColor(person.id).opacity(0.1),in:Circle())
                                    Text(person.name).font(.system(size:14)).lineLimit(2)
                                    Spacer()
                                    if person.id == currentID { Image(systemName:"checkmark").foregroundStyle(MeetingStyle.accent) }
                                }.padding(.horizontal,16).padding(.vertical,10).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(!enabled || busy)
                        }
                    }
                }.frame(height:min(220,CGFloat(matches.count)*58))
            } else if !canAdd {
                Text(L10n.tr(clean.count > 60 ? "姓名最多 60 个字" : "搜索或添加新的说话人"))
                    .font(.system(size:13)).foregroundStyle(.secondary).frame(maxWidth:.infinity,minHeight:100)
            }
            Divider()
            VStack(alignment:.leading,spacing:8) {
                Text(L10n.tr(busy ? "正在应用姓名…" : footer)).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                if canUndo { Button(L10n.tr("撤销上次修改"),action:undo).font(.caption).buttonStyle(.borderless).disabled(busy || !enabled) }
            }.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,16).padding(.vertical,10)
        }.frame(width:330).onAppear { focused = true }
    }
    private func submit() {
        guard enabled, !busy else { return }
        if exact.count == 1, let person = exact.first { select(person) }
        else if canAdd { add(clean) }
    }
}
