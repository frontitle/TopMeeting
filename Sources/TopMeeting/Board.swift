import Foundation

struct NoteSection: Identifiable {
    var id: Int
    var title: String
    var body: String
    static func parse(_ markdown: String) -> [NoteSection] {
        var sections: [NoteSection] = []
        var title = "会议摘要", lines: [String] = []
        func flush() {
            let body = lines.joined(separator:"\n").trimmingCharacters(in:.whitespacesAndNewlines)
            if !body.isEmpty { sections.append(NoteSection(id:sections.count,title:title,body:body)) }
        }
        for line in markdown.components(separatedBy:.newlines) {
            if line.hasPrefix("#") {
                flush(); title = line.drop(while:{$0 == "#" || $0 == " "}).description; lines = []
            } else { lines.append(line) }
        }
        flush(); return sections
    }
}
