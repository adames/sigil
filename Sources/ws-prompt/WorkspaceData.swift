import Foundation

/// Read-side model for the focus / send prompts. Carries only the fields
/// the overlay needs to render the workspace list.
///
/// Sourcing the workspace list — joining aerospace's live workspaces
/// with spaces.json identity entries — lives in `WorkspaceService`,
/// not here. This file is just the data shape.
struct Workspace: Equatable {
    let index: Int          // 1-based ordinal within the workspace list
    let name: String        // user-given name or "ws<index>" fallback
    let color: String       // "#RRGGBB"
    let icon: String?       // resolved glyph (Nerd Font glyph or SF Symbol name)
    let iconKind: IconKind  // disambiguates how to render `icon`
    let iconFontFamily: String?  // set for .nerdFont — the font that owns the glyph

    enum IconKind { case none, sfSymbol, nerdFont }
}
