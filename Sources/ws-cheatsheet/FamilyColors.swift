import SwiftUI

/// Categorical color tokens, one per "world" the user works in.
/// Four colors form a tight perceptual band — small enough that the cue
/// stays strong, distinct enough that the columns read as four worlds.
///
/// Sections share a family color; a section's identity is carried by its
/// title + idea caption, not by a unique hue.
enum FamilyColors {
    static let system   = Color(hex: "#60a5fa") ?? .blue     // Hyper / Mod  (window mgr, workspace, launch)
    static let terminal = Color(hex: "#34d399") ?? .green    // Tmux, shell
    static let vim      = Color(hex: "#fb923c") ?? .orange   // Raw vim keys (motion, edit)
    static let nvim     = Color(hex: "#cba6f7") ?? .purple   // Neovim plugin layer (LSP, fzf, oil, marks)

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
