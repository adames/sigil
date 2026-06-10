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
/// monitor share one vocabulary. Number-only: a digit picks a slot and
/// esc cancels — there is no text query, so no enter / tab / backspace.
enum PromptKey: Equatable {
    case char(Character)
    case escape
}

/// Outcome of a key. The host spawns ws-send-follow on `.commitSend` and
/// tears the overlay down on `.commitSend` / `.cancel`.
enum PromptAction: Equatable {
    case idle
    case commitSend(slot: Int)
    case cancel
}

/// State machine for the send (follow) prompt. Modeled on AeroSpace's
/// numeric workspace switch: a digit commits its slot immediately (1…9,
/// and `0` → slot 10), esc cancels, every other key is a no-op. No name
/// search and no selection state — the overlay just lists the workspaces
/// so you can see which number is which.
///
/// SwiftUI binds via `@ObservedObject`; the controller owns no NSEvent /
/// NSApp — keys arrive through `handle(_:)` and the host spawns the
/// ws-send-follow helper once a `commitSend` action is emitted.
final class PromptController: ObservableObject {
    let mode: PromptMode
    let workspaces: [Workspace]

    init(mode: PromptMode, workspaces: [Workspace]) {
        self.mode = mode
        self.workspaces = workspaces
    }

    /// Drive the state machine. One key in, one Action out.
    func handle(_ key: PromptKey) -> PromptAction {
        switch key {
        case .escape:
            return .cancel
        case .char(let c):
            guard c.isASCII, c.isNumber else { return .idle }
            return commitDigit(c)
        }
    }

    /// Fold a key list through `handle`, returning the first commit/cancel
    /// (or `.idle` if the input ran dry). Backs the `--simulate-keys`
    /// smoke harness.
    func simulate(_ keys: [PromptKey]) -> PromptAction {
        for key in keys {
            let action = handle(key)
            switch action {
            case .commitSend, .cancel:
                return action
            case .idle:
                continue
            }
        }
        return .idle
    }

    private func commitDigit(_ c: Character) -> PromptAction {
        // `0` is the convention-mapped alias for slot 10 so the digit row
        // stays visually contiguous (1…9, 0). Caller gated on isNumber, so
        // the Int() unwrap is total.
        let slot = (c == "0") ? 10 : Int(String(c))!
        // Workspace indices are contiguous 1…count, so this rejects any
        // digit with no listed workspace. ws-send-follow re-validates,
        // but cancelling here skips spawning a helper that can only fail.
        guard slot <= workspaces.count else {
            return .cancel
        }
        return .commitSend(slot: slot)
    }
}
