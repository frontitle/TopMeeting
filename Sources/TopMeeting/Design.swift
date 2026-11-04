import SwiftUI

enum MeetingStyle {
    static let brand = Color(red:0.20,green:0.32,blue:0.92)
    static let accent = Color(nsColor:NSColor(name:nil) { appearance in
        appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
            ? NSColor(srgbRed:0.55,green:0.64,blue:1,alpha:1)
            : NSColor(srgbRed:0.20,green:0.32,blue:0.92,alpha:1)
    })
    static let canvas = Color(nsColor:NSColor(name:nil) { appearance in
        appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
            ? NSColor(srgbRed:0.10,green:0.11,blue:0.14,alpha:1)
            : NSColor(srgbRed:0.965,green:0.972,blue:0.985,alpha:1)
    })
    static let surface = Color(nsColor:.textBackgroundColor)
    static let border = Color.primary.opacity(0.065)
    static func personColor(_ identity: String) -> Color {
        let colors: [Color] = [accent,.teal,.indigo,.orange,.pink]
        let index = identity.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % colors.count }
        return colors[index]
    }
    static func sectionSymbol(_ title: String) -> String {
        if title.contains("待办") || title.contains("行动") { return "checklist" }
        if title.contains("决策") { return "checkmark.seal" }
        if title.contains("问题") || title.contains("确认") { return "questionmark.bubble" }
        if title.contains("摘要") { return "sparkles" }
        return "text.alignleft"
    }
}
struct MeetingBadge: View {
    let title: String
    var symbol: String = "circle.fill"
    var tint: Color = MeetingStyle.accent
    var body: some View {
        Label(L10n.tr(title),systemImage:symbol).font(.system(size:11,weight:.medium))
            .foregroundStyle(tint).padding(.horizontal,9).padding(.vertical,5)
            .background(tint.opacity(0.08),in:Capsule())
    }
}
struct MeetingCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(18).background(MeetingStyle.surface,in:RoundedRectangle(cornerRadius:16))
            .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(MeetingStyle.border))
    }
}

struct MeetingPrimaryButtonStyle: ButtonStyle {
    var tint: Color = MeetingStyle.brand
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.white).padding(.horizontal,10).padding(.vertical,6)
            .background(tint.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),in:RoundedRectangle(cornerRadius:10))
            .contentShape(RoundedRectangle(cornerRadius:10))
    }
}
