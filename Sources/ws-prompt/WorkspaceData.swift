import Foundation

/// Read-side model for the focus / send prompts and the manage overlay's
/// target picker. Carries only the fields the overlay needs to render a
/// list and resolve a typed query.
///
/// Sourcing the workspace list — joining aerospace's live workspaces
/// with spaces.json identity entries — lives in `WorkspaceService`,
/// not here. This file is just the data shape.
struct Workspace: Equatable {
    let index: Int          // 1-based ordinal within the workspace list
    let display: Int        // aerospace monitor ordinal this workspace lives on
    let name: String        // user-given name or "ws<index>" fallback
    let color: String       // "#RRGGBB"
    let icon: String?       // resolved glyph (Nerd Font codepoint or SF Symbol name)
    let iconKind: IconKind  // disambiguates how to render `icon`

    enum IconKind { case none, sfSymbol, nerdFont }
}
