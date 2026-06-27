import Foundation
import SwiftUI
import WsUI

/// A single input event the controller understands. Same vocabulary as
/// ws-prompt's PromptKey — kept local because the two binaries don't
/// share a controller and copying one enum keeps WsUI free of
/// app-specific types.
enum PickerKey: Equatable {
    case char(Character)
    case enter
    case escape
    case tab
    case backTab
    case backspace
}

/// Outcome of a key. The UI re-renders on every event; the binary
/// dispatches `aerospace -m window --focus` on `.commit`.
enum PickerAction: Equatable {
    case idle
    case refilter
    case commit(id: Int)
    case cancel
}

/// State machine for the window picker. Mirrors `PromptController`'s
/// shape — letters build a fuzzy query, Tab cycles matches, Enter
/// commits, Esc cancels. No digit-fast-path: window IDs are 6-digit
/// aerospace handles, not slot numbers.
final class PickerController: ObservableObject {
    /// Window list. Starts empty and is filled by `apply(...)` once the
    /// async aerospace query returns, so the overlay paints immediately.
    @Published private(set) var items: [WindowItem]
    /// True until the first `apply(...)`. While loading, Enter is a no-op
    /// (there's nothing to commit yet) instead of dismissing the picker.
    @Published private(set) var isLoading: Bool

    @Published private(set) var query: String = ""
    @Published private(set) var selection: Int = 0

    /// `loading: true` for the live overlay (data arrives via `apply`);
    /// `false` when the caller already has the list (the simulate harness).
    init(items: [WindowItem] = [], loading: Bool = false) {
        self.items = items
        self.isLoading = loading
    }

    /// Replace the window list once the async query lands and clear the
    /// loading flag. Selection resets to the top match.
    func apply(items: [WindowItem]) {
        self.items = items
        self.selection = 0
        self.isLoading = false
    }

    func handle(_ key: PickerKey) -> PickerAction {
        switch key {
        case .escape:
            return .cancel
        case .enter:
            return commitFromQuery()
        case .tab:
            return cycle(by: +1)
        case .backTab:
            return cycle(by: -1)
        case .backspace:
            if query.isEmpty { return .idle }
            query.removeLast()
            selection = 0
            return .refilter
        case .char(let c):
            query.append(Character(String(c).lowercased()))
            selection = 0
            return .refilter
        }
    }

    /// Fold a list of keys through `handle` and return the final
    /// non-idle action. Backs the `--simulate-keys` smoke hook.
    func simulate(_ keys: [PickerKey]) -> PickerAction {
        var last: PickerAction = .idle
        for key in keys {
            let action = handle(key)
            switch action {
            case .commit, .cancel:    return action
            case .refilter:           last = action
            case .idle:               continue
            }
        }
        return last
    }

    private func commitFromQuery() -> PickerAction {
        // List not loaded yet — nothing to commit; ignore rather than
        // treating it as an empty-match cancel.
        if isLoading { return .idle }
        let matches = currentMatches()
        guard !matches.isEmpty else { return .cancel }
        let pick = matches[selection.clamped(to: 0...(matches.count - 1))]
        return .commit(id: pick.id)
    }

    private func cycle(by delta: Int) -> PickerAction {
        let count = currentMatches().count
        guard count > 0 else { return .idle }
        selection = ((selection + delta) % count + count) % count
        return .refilter
    }

    func currentMatches() -> [WindowItem] {
        FuzzyMatch.filter(items, query: query, keyPath: { $0.matchKey })
    }
}
