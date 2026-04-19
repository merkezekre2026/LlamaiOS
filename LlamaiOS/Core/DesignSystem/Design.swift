import SwiftUI

enum Design {
    static let background = Color(red: 0.035, green: 0.039, blue: 0.047)
    static let surface = Color(red: 0.071, green: 0.078, blue: 0.094)
    static let elevated = Color(red: 0.105, green: 0.114, blue: 0.133)
    static let assistantBubble = Color(red: 0.118, green: 0.129, blue: 0.153)
    static let userBubble = Color(red: 0.125, green: 0.285, blue: 0.255)
    static let accent = Color(red: 0.329, green: 0.769, blue: 0.647)
    static let warning = Color(red: 0.945, green: 0.615, blue: 0.255)
    static let danger = Color(red: 0.925, green: 0.298, blue: 0.314)
    static let secondaryText = Color.white.opacity(0.66)
    static let separator = Color.white.opacity(0.08)
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Design.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}
