import Testing
@testable import ws_prompt

/// Builds a small fixture list of `count` workspaces, 1-based `index`
/// matching position — mirrors how `ProductionWorkspaceService` numbers
/// workspaces by their ordinal position in the live aerospace list.
private func fixtureWorkspaces(_ count: Int) -> [Workspace] {
    (1...count).map { i in
        Workspace(
            index: i,
            name: "ws\(i)",
            color: "#7f8c8d",
            icon: nil,
            iconKind: .none,
            iconFontFamily: nil
        )
    }
}

@Suite("PromptController — digit fast-path")
struct PromptControllerDigitTests {
    @Test func digit_within_range_commits_that_slot_and_moves_selection() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(5))
        let action = c.handle(.char("3"))
        #expect(action == .commitSend(slot: 3))
        #expect(c.selection == 2)
    }

    @Test func digit_one_commits_slot_one() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(3))
        #expect(c.handle(.char("1")) == .commitSend(slot: 1))
        #expect(c.selection == 0)
    }

    @Test func zero_is_the_alias_for_slot_ten() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(10))
        let action = c.handle(.char("0"))
        #expect(action == .commitSend(slot: 10))
        #expect(c.selection == 9)
    }

    @Test func zero_alias_rejects_when_fewer_than_ten_workspaces() {
        // 0 always means "slot 10" — with only 5 workspaces that's out of
        // range, same as any other out-of-range digit.
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(5))
        let action = c.handle(.char("0"))
        #expect(action == .reject)
        #expect(c.nudge == 1)
    }

    @Test func out_of_range_digit_rejects_and_nudges_without_moving_selection() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(3))
        #expect(c.nudge == 0)
        let action = c.handle(.char("9"))
        #expect(action == .reject)
        #expect(c.nudge == 1)
        // Selection must be untouched by a rejected digit.
        #expect(c.selection == 0)
    }

    @Test func repeated_out_of_range_digits_accumulate_nudge() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(2))
        _ = c.handle(.char("8"))
        _ = c.handle(.char("9"))
        #expect(c.nudge == 2)
    }

    @Test func non_digit_char_is_idle() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(3))
        #expect(c.handle(.char("a")) == .idle)
        #expect(c.nudge == 0)
    }

    @Test func digit_commits_optimistically_while_loading_even_if_out_of_range() {
        // isLoading gates validation, not commit: the digit fast-path is
        // meant to stay instant on caps+f-then-digit, trusting
        // ws-send-follow to reject a bad slot downstream.
        let c = PromptController(mode: .send, workspaces: [], loading: true)
        let action = c.handle(.char("7"))
        #expect(action == .commitSend(slot: 7))
        // No nudge — this path never touches the reject branch.
        #expect(c.nudge == 0)
    }

    @Test func zero_alias_also_commits_optimistically_while_loading() {
        let c = PromptController(mode: .send, workspaces: [], loading: true)
        #expect(c.handle(.char("0")) == .commitSend(slot: 10))
    }
}

@Suite("PromptController — tab / shift-tab cycling")
struct PromptControllerCyclingTests {
    @Test func tab_advances_selection_by_one() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(4))
        #expect(c.handle(.tab) == .move)
        #expect(c.selection == 1)
    }

    @Test func down_behaves_like_tab() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(4))
        #expect(c.handle(.down) == .move)
        #expect(c.selection == 1)
    }

    @Test func tab_wraps_from_last_to_first() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(3))
        _ = c.handle(.tab) // 0 -> 1
        _ = c.handle(.tab) // 1 -> 2 (last)
        #expect(c.selection == 2)
        _ = c.handle(.tab) // 2 -> wraps to 0
        #expect(c.selection == 0)
    }

    @Test func shift_tab_wraps_from_first_to_last() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(3))
        #expect(c.selection == 0)
        let action = c.handle(.backTab)
        #expect(action == .move)
        #expect(c.selection == 2) // last index for a 3-item list
    }

    @Test func up_behaves_like_shift_tab() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(3))
        #expect(c.handle(.up) == .move)
        #expect(c.selection == 2)
    }

    @Test func cycling_with_no_workspaces_is_idle_and_does_not_crash() {
        let c = PromptController(mode: .send, workspaces: [])
        #expect(c.handle(.tab) == .idle)
        #expect(c.handle(.backTab) == .idle)
        #expect(c.selection == 0)
    }

    @Test func repeated_wraparound_is_stable_modular_arithmetic() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(2))
        // 0 -> 1 -> 0 -> 1 ...
        _ = c.handle(.tab)
        #expect(c.selection == 1)
        _ = c.handle(.tab)
        #expect(c.selection == 0)
        _ = c.handle(.backTab)
        #expect(c.selection == 1)
    }
}

@Suite("PromptController — escape / cancel")
struct PromptControllerEscapeTests {
    @Test func escape_cancels_regardless_of_state() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(5))
        #expect(c.handle(.escape) == .cancel)
    }

    @Test func escape_cancels_even_while_loading() {
        let c = PromptController(mode: .send, workspaces: [], loading: true)
        #expect(c.handle(.escape) == .cancel)
    }
}

@Suite("PromptController — enter / commit selection")
struct PromptControllerCommitTests {
    @Test func enter_commits_currently_selected_slot() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(4))
        _ = c.handle(.tab) // move to index 1 (slot 2)
        let action = c.handle(.enter)
        #expect(action == .commitSend(slot: 2))
    }

    @Test func enter_with_no_workspaces_rejects_rather_than_commits() {
        let c = PromptController(mode: .send, workspaces: [])
        let action = c.handle(.enter)
        #expect(action == .reject)
    }
}

@Suite("PromptController — apply resets loading + selection")
struct PromptControllerApplyTests {
    @Test func apply_clears_loading_and_resets_selection_to_first_row() {
        let c = PromptController(mode: .send, workspaces: [], loading: true)
        _ = c.handle(.tab) // no-op: empty list
        c.apply(workspaces: fixtureWorkspaces(3))
        #expect(c.isLoading == false)
        #expect(c.selection == 0)
        #expect(c.workspaces.count == 3)
    }

    @Test func after_apply_out_of_range_digit_is_validated_against_new_list() {
        let c = PromptController(mode: .send, workspaces: [], loading: true)
        c.apply(workspaces: fixtureWorkspaces(2))
        // Once loaded, digit fast-path is validated again (no longer
        // optimistic) — 5 is now out of range for a 2-item list.
        let action = c.handle(.char("5"))
        #expect(action == .reject)
        #expect(c.nudge == 1)
    }
}

@Suite("PromptController — simulate folds keys to one action")
struct PromptControllerSimulateTests {
    @Test func simulate_stops_at_first_commit() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(5))
        let result = c.simulate([.tab, .tab, .char("3")])
        #expect(result == .commitSend(slot: 3))
    }

    @Test func simulate_stops_at_first_cancel() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(5))
        let result = c.simulate([.tab, .escape, .char("3")])
        #expect(result == .cancel)
    }

    @Test func simulate_returns_last_non_idle_action_when_no_commit_or_cancel() {
        let c = PromptController(mode: .send, workspaces: fixtureWorkspaces(2))
        // Trailing idle (letter 'z') must not overwrite the last real action.
        let result = c.simulate([.tab, .char("z")])
        #expect(result == .move)
    }
}
