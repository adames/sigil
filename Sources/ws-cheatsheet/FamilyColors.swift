import SwiftUI
import WsUI   // re-exports Palette / Catppuccin

/// Categorical color tokens, one per "world" the user works in. Each
/// family maps to a resolved-palette accent so every sigil surface reads
/// off the same palette (the terminal's, falling back to Catppuccin).
///
/// Sections share a family color; a section's identity is carried by its
/// title + idea caption, not by a unique hue.
enum FamilyColors {
    static let system   = Palette.resolved.blue    // Hyper / Mod  (window mgr, workspace, launch)
    static let terminal = Palette.resolved.green    // tmux, shell
    static let vim      = Palette.resolved.peach    // raw vim keys (motion, edit)
    static let nvim     = Palette.resolved.mauve    // nvim plugin layer (LSP, fzf, oil, marks)

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
}
