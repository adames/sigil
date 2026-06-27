import Foundation
import SwiftUI

/// The overlay's sole prompt: **send** (follow) — send the focused window
/// to a workspace and travel with it. The old `focus`/"go" mode was removed
/// (AeroSpace's own Caps+1…0 focuses a workspace by number). Kept as a
/// one-case enum so `ws-prompt send` stays the invocation and a stale
/// `ws-prompt focus` argument is rejected with a usage error.
enum PromptMode: String {
    case send
}

/// A single input event the controller understands. Modeled as a closed
/// enum (rather than raw Strings) so the simulator and the live key
/// monitor share one vocabulary. The send prompt shares the picker's
/// navigation model — arrows/tab move a selection, enter commits — while
/// keeping digits as direct accelerators.
enum PromptKey: Equatable {
    case char(Character)
    case escape
    case enter
    case up
    case down
    case tab
    case backTab
}

/// Outcome of a key. The host spawns ws-send-follow on `.commitSend` and
/// tears the overlay down on `.commitSend` / `.cancel`. `.move` re-renders
/// the selection; `.reject` flashes the card (input that maps to no slot).
enum PromptAction: Equatable {
    case idle
    case move
    case reject
    case commitSend(slot: Int)
    case cancel
}

/// State machine for the send (follow) prompt. Shares the window picker's
/// interaction model so the two overlays — which look identical — also
/// behave identically: a highlighted selection that arrows/tab move, enter
/// commits, esc cancels. Digits stay as direct accelerators (1…9, and
/// `0` → slot 10) for muscle memory, and a digit past the last workspace
/// nudges the card rather than silently dismissing.
///
/// SwiftUI binds via `@ObservedObject`; the controller owns no NSEvent /
/// NSApp — keys arrive through `handle(_:)` and the host spawns the
/// ws-send-follow helper once a `commitSend` action is emitted.
final class PromptController: ObservableObject {
    let mode: PromptMode

    /// Live workspace list. Starts empty and is filled by `apply(...)` once
    /// the async AeroSpace query returns — the window paints first, the
    /// rows arrive a beat later.
    @Published private(set) var workspaces: [Workspace]
    /// True until the first `apply(...)`. While loading, a digit commits
    /// optimistically (ws-send-follow validates the slot) so the common
    /// caps+f-then-digit path isn't gated on the query.
    @Published private(set) var isLoading: Bool

    /// 0-based index into `workspaces` of the highlighted row.
    @Published private(set) var selection: Int = 0
    /// Bumped on each rejected input so the view can shake once.
    @Published private(set) var nudge: Int = 0

    /// `loading: true` for the live overlay (data arrives via `apply`);
    /// `false` when the caller already has the list (the simulate harness).
    init(mode: PromptMode, workspaces: [Workspace] = [], loading: Bool = false) {
        self.mode = mode
        self.workspaces = workspaces
        self.isLoading = loading
    }

    /// Replace the workspace list once the async query lands and clear the
    /// loading flag. Selection resets to the first row.
    func apply(workspaces: [Workspace]) {
        self.workspaces = workspaces
        self.selection = 0
        self.isLoading = false
    }

    /// Drive the state machine. One key in, one Action out.
    func handle(_ key: PromptKey) -> PromptAction {
        switch key {
        case .escape:
            return .cancel
        case .enter:
            return commitSelection()
        case .down, .tab:
            return move(by: +1)
        case .up, .backTab:
            return move(by: -1)
        case .char(let c):
            guard c.isASCII, c.isNumber else { return .idle }
            return commitDigit(c)
        }
    }

    /// Fold a key list through `handle`, returning the first commit/cancel
    /// (or the last non-idle action otherwise). Backs the `--simulate-keys`
    /// smoke harness.
    func simulate(_ keys: [PromptKey]) -> PromptAction {
        var last: PromptAction = .idle
        for key in keys {
            let action = handle(key)
            switch action {
            case .commitSend, .cancel:
                return action
            case .move, .reject:
                last = action
            case .idle:
                continue
            }
        }
        return last
    }

    private func move(by delta: Int) -> PromptAction {
        let count = workspaces.count
        guard count > 0 else { return .idle }
        selection = ((selection + delta) % count + count) % count
        return .move
    }

    private func commitSelection() -> PromptAction {
        guard !workspaces.isEmpty else { return .reject }
        // workspaces[selection].index is the 1-based slot ws-send-follow wants.
        return .commitSend(slot: workspaces[selection.clamped(to: 0...(workspaces.count - 1))].index)
    }

    private func commitDigit(_ c: Character) -> PromptAction {
        // `0` is the convention-mapped alias for slot 10 so the digit row
        // stays visually contiguous (1…9, 0). Caller gated on isNumber, so
        // the Int() unwrap is total.
        let slot = (c == "0") ? 10 : Int(String(c))!
        // List not loaded yet: commit the digit as-is and let ws-send-follow
        // validate the slot ("slot N does not exist"). Keeps caps+f-then-digit
        // instant instead of waiting on the workspace query.
        if isLoading {
            return .commitSend(slot: slot)
        }
        // Workspace indices are contiguous 1…count. A digit past the last
        // workspace is a user miss — nudge the card so the no-op is
        // visible, rather than silently tearing the overlay down.
        guard slot <= workspaces.count else {
            nudge += 1
            return .reject
        }
        selection = slot - 1
        return .commitSend(slot: slot)
    }
}
