import SwiftUI

// MARK: - Catppuccin Mocha palette
//
// Complete Catppuccin Mocha tokens, ordered as they're laid out in the
// upstream palette: backgrounds → surfaces → overlays → text → accents.
// Shared across every sigil overlay so the cheatsheet, prompts, and
// picker read as one surface.
//
// Caseless struct (vs enum) follows the Swift convention for "namespace
// for constants" — `enum` is conventionally for tagged unions.

public struct Catppuccin {
    // Backgrounds (darkest → lightest base layer)
    public static let crust    = Color(hex: "#11111b") ?? .black
    public static let mantle   = Color(hex: "#181825") ?? .black
    public static let base     = Color(hex: "#1e1e2e") ?? .black

    // Elevated surfaces (cards, fills)
    public static let surface0 = Color(hex: "#313244") ?? .gray
    public static let surface1 = Color(hex: "#45475a") ?? .gray
    public static let surface2 = Color(hex: "#585b70") ?? .gray

    // Overlays (borders, dividers, low-emphasis text)
    public static let overlay0 = Color(hex: "#6c7086") ?? .gray
    public static let overlay1 = Color(hex: "#7f849c") ?? .gray
    public static let overlay2 = Color(hex: "#9399b2") ?? .gray

    // Text (foreground hierarchy)
    public static let subtext0 = Color(hex: "#a6adc8") ?? .white
    public static let subtext1 = Color(hex: "#bac2de") ?? .white
    public static let text     = Color(hex: "#cdd6f4") ?? .white

    // Accents
    public static let rosewater = Color(hex: "#f5e0dc") ?? .white
    public static let flamingo  = Color(hex: "#f2cdcd") ?? .pink
    public static let pink      = Color(hex: "#f5c2e7") ?? .pink
    public static let mauve     = Color(hex: "#cba6f7") ?? .purple
    public static let red       = Color(hex: "#f38ba8") ?? .red
    public static let maroon    = Color(hex: "#eba0ac") ?? .pink
    public static let peach     = Color(hex: "#fab387") ?? .orange
    public static let yellow    = Color(hex: "#f9e2af") ?? .yellow
    public static let green     = Color(hex: "#a6e3a1") ?? .green
    public static let teal      = Color(hex: "#94e2d5") ?? .teal
    public static let sky       = Color(hex: "#89dceb") ?? .cyan
    public static let sapphire  = Color(hex: "#74c7ec") ?? .blue
    public static let blue      = Color(hex: "#89b4fa") ?? .blue
    public static let lavender  = Color(hex: "#b4befe") ?? .indigo

    private init() {}
}

// MARK: - Shape + typography tokens

public struct PromptStyle {
    /// SF Symbols for all icons — native Apple icon system.
    public static let iconFont: Font = .system(size: 16, weight: .medium)

    public static func icon(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium)
    }

    public static let pillCorner: CGFloat = 6
    public static let pillHeight: CGFloat = 22
    public static let cardCorner: CGFloat = 10

    /// Distance from the top of the screen to the top of the overlay
    /// card. Matches Raycast's search-box top so the two surfaces feel
    /// like part of the same launcher family.
    public static let topInset: CGFloat = 120

    private init() {}
}

// MARK: - Comparable.clamped

public extension Comparable {
    /// Clamp `self` to a closed range. Used in overlay pickers where the
    /// SwiftUI selection index can briefly outlive the filtered list during
    /// a refilter.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
