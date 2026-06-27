import SwiftUI
import WsUI   // re-exports Palette / Catppuccin

/// Categorical color tokens, one per "world" the user works in. The
/// resolver writes these from the tools' own config-derived colors into
/// palette.json; when absent, the old resolved-palette accents remain the
/// fallback.
///
/// Sections share a family color; a section's identity is carried by its
/// title + idea caption, not by a unique hue.
enum FamilyColors {
    private static let derived = Palette.loadFamilies()

    static let system   = derivedColor("system")   ?? Palette.resolved.blue    // Hyper / Mod
    static let terminal = derivedColor("terminal") ?? Palette.resolved.green   // tmux, shell
    static let vim      = derivedColor("vim")      ?? Palette.resolved.peach   // raw vim keys
    static let nvim     = derivedColor("nvim")     ?? Palette.resolved.mauve   // nvim plugin layer

    /// Resolve a section's effective accent color. Prefers the new `family`
    /// token; falls back to the legacy per-section `color` hex.
    static func resolve(family: String?, fallbackHex: String) -> Color {
        if let family, let c = color(forFamily: family) { return c }
        return Color(hex: fallbackHex) ?? .accentColor
    }

    static func color(forFamily family: String) -> Color? {
        switch family.lowercased() {
        case "system":   return system
        case "terminal": return terminal
        case "vim":      return vim
        case "nvim":     return nvim
        default:         return nil
        }
    }

    private static func derivedColor(_ family: String) -> Color? {
        guard let hex = derived[family.lowercased()] else { return nil }
        return Color(hex: hex)
    }
}
