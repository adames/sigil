import Foundation

/// One row in the picker — a window snapshot reduced to the fields the
/// overlay renders or matches against. Mapped from
/// `WindowManager.queryWindows()` at load time.
struct WindowItem: Equatable, Identifiable {
    let id: Int
    let app: String
    let title: String
    let space: Int
    let display: Int

    /// Combined string used for fuzzy matching. Including the space and
    /// display indices lets the user reach by workspace number ("3 term"
    /// finds the Ghostty on space 3) without juggling separate filters.
    var matchKey: String {
        let titleSegment = title.isEmpty ? "" : " \(title)"
        return "\(app)\(titleSegment) \(space) \(display)"
    }

    /// What the row shows in the title column. Falls back to app name
    /// when the window has no title (common for new app windows that
    /// haven't loaded their document yet).
    var displayLabel: String {
        title.isEmpty ? app : title
    }
}
