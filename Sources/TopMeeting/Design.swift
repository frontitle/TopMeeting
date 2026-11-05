import SwiftUI

enum MeetingStyle {
    static let brand = Color(nsColor:.labelColor)
    static let accent = Color(nsColor:NSColor(name:nil) { appearance in
        appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
            ? NSColor(srgbRed:0.65,green:0.77,blue:0.94,alpha:1)
            : NSColor(srgbRed:0.22,green:0.36,blue:0.56,alpha:1)
    })
    static let canvas = Color(nsColor:NSColor(name:nil) { appearance in
        appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
            ? NSColor(srgbRed:0.13,green:0.135,blue:0.125,alpha:1)
            : NSColor(srgbRed:0.975,green:0.975,blue:0.97,alpha:1)
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
        content.padding(16).background(MeetingStyle.surface,in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(MeetingStyle.border))
    }
}

struct MeetingPrimaryButtonStyle: ButtonStyle {
    var tint: Color = MeetingStyle.brand
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(tint == MeetingStyle.brand ? Color(nsColor:.textBackgroundColor) : .white).padding(.horizontal,10).padding(.vertical,6)
            .background(tint.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),in:RoundedRectangle(cornerRadius:8))
            .contentShape(RoundedRectangle(cornerRadius:8))
    }
}
