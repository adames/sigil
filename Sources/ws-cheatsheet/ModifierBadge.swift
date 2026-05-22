import SwiftUI

/// A small leading glyph that classifies "which world this key lives in"
/// at a glance — Gestalt similarity reinforcing the spatial proximity that
/// already groups sections by family.
///
/// Classification is a pure function over the chord string so JSON authors
/// don't have to annotate each row.
enum ModifierFamily {
    case hyper           // caps + …            (system layer, ⌃⌥⌘⇧)
    case mod             // caps + shift + …    (system layer modify, ⌃⌥⌘)
    case tmuxPrefix      // C-a … / C-Space …   (terminal)
    case raw             // everything else     (vim motion/edit, shell aliases, etc.)

    var color: Color {
        switch self {
        case .hyper, .mod:    return FamilyColors.system
        case .tmuxPrefix:     return FamilyColors.terminal
        case .raw:            return Color.white.opacity(0.22)
        }
    }

    static func classify(_ chord: String) -> ModifierFamily {
        let s = chord.lowercased()
        if s.hasPrefix("caps + shift")   { return .mod }
        if s.hasPrefix("caps +")         { return .hyper }
        if s.hasPrefix("c-a") || s.hasPrefix("c-space") { return .tmuxPrefix }
        return .raw
    }
}

struct ModifierBadge: View {
    let family: ModifierFamily
    var size: CGFloat = 5

    init(_ family: ModifierFamily, size: CGFloat = 5) {
        self.family = family
        self.size = size
    }

    init(forChord chord: String, size: CGFloat = 5) {
        self.family = ModifierFamily.classify(chord)
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(family.color)
            .frame(width: size, height: size)
            .opacity(family == .raw ? 0.55 : 0.95)
    }
}
