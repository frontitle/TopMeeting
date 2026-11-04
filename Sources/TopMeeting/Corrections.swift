import Foundation

struct TermCorrection: Codable, Identifiable, Equatable {
    var id = UUID()
    var heard: String
    var preferred: String
    var date = Date()
}

extension Line {
    mutating func replaceSelection(_ range: NSRange, with replacement: String, expected: String) throws -> String {
        guard text == expected, live != true else { throw Gateway.error("这段实录已更新，请重新选中要纠正的文字。") }
        guard range.length > 0, let selection = Range(range,in:text), !replacement.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, replacement.count <= 120 else { throw Gateway.error("请选择有效词语并填写正确写法。") }
        let old = text, selected = String(text[selection])
        guard selected != replacement else { return selected }
        if let words {
            let source = old as NSString
            var cursor = 0, locations: [NSRange] = []
            for word in words {
                let found = source.range(of:word.text,range:NSRange(location:cursor,length:source.length-cursor))
                if found.location == NSNotFound { locations = []; break }
                locations.append(found); cursor = NSMaxRange(found)
            }
            let touched = locations.indices.filter { NSIntersectionRange(locations[$0],range).length > 0 }
            if let first = touched.first, let last = touched.last {
                let lower = min(locations[first].location,range.location)
                let upper = max(NSMaxRange(locations[last]),NSMaxRange(range))
                let fragment = source.substring(with:NSRange(location:lower,length:upper-lower)) as NSString
                let rewritten = fragment.replacingCharacters(in:NSRange(location:range.location-lower,length:range.length),with:replacement)
                var updated = words
                updated.replaceSubrange(first...last,with:[SpeechWord(text:rewritten,start:words[first].start,end:words[last].end)])
                self.words = updated
            } else {
                // Punctuation-only edits preserve approximate word times; text ranges
                // are still checked against the exact source before changing anything.
                if !locations.isEmpty {
                    let index = locations.lastIndex(where:{NSMaxRange($0) <= range.location}) ?? 0
                    let lower = min(locations[index].location,range.location)
                    let upper = max(index+1 < locations.count ? locations[index+1].location : source.length,NSMaxRange(range))
                    let fragment = source.substring(with:NSRange(location:lower,length:upper-lower)) as NSString
                    var updated = words
                    updated[index].text = fragment.replacingCharacters(in:NSRange(location:range.location-lower,length:range.length),with:replacement)
                    self.words = updated
                }
            }
        }
        original = original ?? old
        text = (old as NSString).replacingCharacters(in:range,with:replacement)
        inlineCorrected = true
        return selected
    }
}

func recognitionTerms(_ corrections: [TermCorrection], names: [String] = []) -> [String] {
    var seen = Set<String>(), result: [String] = []
    for phrase in corrections.reversed().map(\.preferred) + names {
        let clean = phrase.trimmingCharacters(in:.whitespacesAndNewlines)
        if !clean.isEmpty, clean.count <= 80, seen.insert(clean).inserted { result.append(clean) }
        if result.count == 100 { break }
    }
    return result
}
