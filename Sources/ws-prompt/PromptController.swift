import Foundation
import SwiftUI

/// The two prompts the overlay can render, picked from the first CLI arg.
/// Both share this one state machine — the only difference is which helper
/// the host spawns on commit (ws-focus vs ws-send-follow).
enum PromptMode: String {
    case focus, send
}

/// A single input event the controller understands. Modeled as a closed
/// enum (rather than raw Strings) so the simulator and the live key
/// monitor share one vocabulary. Number-only: a digit picks a slot and
/// esc cancels — there is no text query, so no enter / tab / backspace.
enum PromptKey: Equatable {
    case char(Character)
    case escape
}

/// Outcome of a key. The host spawns the side-effect helper on `.commit*`
/// and tears the overlay down on `.commit*` / `.cancel`.
enum PromptAction: Equatable {
    case idle
    case commitFocus(slot: Int)
    case commitSend(slot: Int)
    case cancel
}

/// State machine for the focus / send prompts. Modeled on AeroSpace's own
/// numeric workspace switch: a digit commits its slot immediately (1…9,
/// and `0` → slot 10), esc cancels, every other key is a no-op. No name
/// search and no selection state — the overlay just lists the workspaces
/// so you can see which number is which.
///
/// SwiftUI binds via `@ObservedObject`; the controller owns no NSEvent /
/// NSApp — keys arrive through `handle(_:)` and the host spawns the focus
/// / send helper once a `commit*` action is emitted.
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
            case .commitFocus, .commitSend, .cancel:
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
        guard slot >= 1, slot <= max(workspaces.last?.index ?? 0, 10) else {
            return .cancel
        }
        return mode == .focus ? .commitFocus(slot: slot) : .commitSend(slot: slot)
    }
}
