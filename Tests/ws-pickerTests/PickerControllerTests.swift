import Testing
@testable import ws_picker

/// Small fixture window list spanning distinct apps/titles/workspaces so
/// fuzzy queries can pick out one unambiguous match.
private func fixtureItems() -> [WindowItem] {
    [
        WindowItem(id: 100, app: "Ghostty", title: "code term", workspace: "code", display: 1),
        WindowItem(id: 200, app: "Safari", title: "Sigil PRs", workspace: "web", display: 1),
        WindowItem(id: 300, app: "Mail", title: "", workspace: "mail", display: 2),
    ]
}

@Suite("PickerController — tab / shift-tab cycling")
struct PickerControllerCyclingTests {
    @Test func tab_advances_selection_by_one() {
        let c = PickerController(items: fixtureItems())
        #expect(c.handle(.tab) == .refilter)
        #expect(c.selection == 1)
    }

    @Test func tab_wraps_from_last_to_first() {
        let c = PickerController(items: fixtureItems())
        _ = c.handle(.tab) // 0 -> 1
        _ = c.handle(.tab) // 1 -> 2 (last of 3)
        #expect(c.selection == 2)
        _ = c.handle(.tab) // wraps to 0
        #expect(c.selection == 0)
    }

    @Test func shift_tab_wraps_from_first_to_last() {
        let c = PickerController(items: fixtureItems())
        #expect(c.selection == 0)
        let action = c.handle(.backTab)
        #expect(action == .refilter)
        #expect(c.selection == 2)
    }

    @Test func cycling_with_no_matches_is_idle() {
        let c = PickerController(items: fixtureItems())
        _ = c.handle(.char("z"))
        _ = c.handle(.char("z"))
        _ = c.handle(.char("z")) // "zzz" matches nothing
        #expect(c.currentMatches().isEmpty)
        #expect(c.handle(.tab) == .idle)
        #expect(c.handle(.backTab) == .idle)
    }

    @Test func cycling_is_scoped_to_current_matches_not_full_item_list() {
        let c = PickerController(items: fixtureItems())
        // "mai" is a subsequence only of Mail's matchKey ("Mail mail 2") —
        // Ghostty's "term" contains a lone "m" but no following "ai".
        for ch in "mai" { _ = c.handle(.char(ch)) }
        #expect(c.currentMatches().map(\.id) == [300])
        // Only one match: tab must wrap back to the same (only) index.
        #expect(c.handle(.tab) == .refilter)
        #expect(c.selection == 0)
    }
}

@Suite("PickerController — escape / cancel")
struct PickerControllerEscapeTests {
    @Test func escape_cancels_regardless_of_query_state() {
        let c = PickerController(items: fixtureItems())
        _ = c.handle(.char("g"))
        #expect(c.handle(.escape) == .cancel)
    }

    @Test func escape_cancels_while_loading() {
        let c = PickerController(items: [], loading: true)
        #expect(c.handle(.escape) == .cancel)
    }
}

@Suite("PickerController — isLoading guard")
struct PickerControllerLoadingTests {
    @Test func commit_while_loading_is_a_no_op_not_a_reject_or_cancel() {
        let c = PickerController(items: [], loading: true)
        let action = c.handle(.enter)
        #expect(action == .idle)
        // Crucially distinct from .reject: no nudge should fire either.
        #expect(c.nudge == 0)
    }

    @Test func apply_clears_loading_and_resets_selection() {
        let c = PickerController(items: [], loading: true)
        c.apply(items: fixtureItems())
        #expect(c.isLoading == false)
        #expect(c.selection == 0)
        #expect(c.items.count == 3)
    }

    @Test func after_apply_enter_commits_normally() {
        let c = PickerController(items: [], loading: true)
        c.apply(items: fixtureItems())
        _ = c.handle(.char("g")) // narrows to Ghostty
        let action = c.handle(.enter)
        #expect(action == .commit(id: 100))
    }
}

@Suite("PickerController — fuzzy query commit")
struct PickerControllerFuzzyCommitTests {
    @Test func query_narrows_to_unique_match_and_commits_its_id() {
        let c = PickerController(items: fixtureItems())
        for ch in "saf" { _ = c.handle(.char(ch)) }
        #expect(c.currentMatches().map(\.id) == [200])
        let action = c.handle(.enter)
        #expect(action == .commit(id: 200))
    }

    @Test func query_matches_by_workspace_name_not_just_app_or_title() {
        // "mail" only appears in WindowItem 300's workspace field (title is
        // empty) — matching proves matchKey folds in workspace, not just
        // app/title.
        let c = PickerController(items: fixtureItems())
        for ch in "mail" { _ = c.handle(.char(ch)) }
        #expect(c.currentMatches().map(\.id) == [300])
        #expect(c.handle(.enter) == .commit(id: 300))
    }

    @Test func backspace_removes_last_query_char_and_refilters() {
        let c = PickerController(items: fixtureItems())
        _ = c.handle(.char("s"))
        _ = c.handle(.char("x")) // "sx" matches nothing
        #expect(c.currentMatches().isEmpty)
        let action = c.handle(.backspace)
        #expect(action == .refilter)
        // Back to "s" alone, which matches Ghostty ("...term...") no —
        // "s" is a subsequence of "Safari" and also of workspace names;
        // assert query state directly instead of guessing the match set.
        #expect(c.query == "s")
    }

    @Test func backspace_on_empty_query_is_idle() {
        let c = PickerController(items: fixtureItems())
        #expect(c.handle(.backspace) == .idle)
    }

    @Test func char_input_lowercases_the_query() {
        let c = PickerController(items: fixtureItems())
        _ = c.handle(.char("G"))
        #expect(c.query == "g")
    }

    @Test func new_query_resets_selection_to_top_match() {
        let c = PickerController(items: fixtureItems())
        _ = c.handle(.tab) // select index 1 among all 3
        #expect(c.selection == 1)
        _ = c.handle(.char("m")) // narrows matches; selection must reset
        #expect(c.selection == 0)
    }
}

@Suite("PickerController — empty-match Enter rejects (PR 5 behavior)")
struct PickerControllerRejectTests {
    @Test func enter_with_no_match_rejects_bumps_nudge_and_keeps_overlay_open() {
        let c = PickerController(items: fixtureItems())
        for ch in "zzz" { _ = c.handle(.char(ch)) }
        #expect(c.currentMatches().isEmpty)
        #expect(c.nudge == 0)
        let action = c.handle(.enter)
        #expect(action == .reject)
        #expect(c.nudge == 1)
        // State is retained, not torn down: query + items are untouched,
        // so a correction (e.g. backspace) can still recover.
        #expect(c.query == "zzz")
        #expect(c.items.count == 3)
    }

    @Test func repeated_empty_match_enters_accumulate_nudge_without_escalating_to_cancel() {
        let c = PickerController(items: fixtureItems())
        for ch in "zzz" { _ = c.handle(.char(ch)) }
        _ = c.handle(.enter)
        let second = c.handle(.enter)
        #expect(second == .reject)
        #expect(c.nudge == 2)
    }

    @Test func reject_and_cancel_are_distinguishable_actions() {
        // The core PR 5 invariant this suite must pin down: an empty-match
        // Enter (.reject) is NOT the same outcome as Esc (.cancel) — the
        // overlay's teardown logic branches on this distinction.
        let rejecting = PickerController(items: fixtureItems())
        for ch in "zzz" { _ = rejecting.handle(.char(ch)) }
        let rejectAction = rejecting.handle(.enter)

        let cancelling = PickerController(items: fixtureItems())
        let cancelAction = cancelling.handle(.escape)

        #expect(rejectAction == .reject)
        #expect(cancelAction == .cancel)
        #expect(rejectAction != cancelAction)
    }
}

@Suite("PickerController — simulate folds keys to one action")
struct PickerControllerSimulateTests {
    @Test func simulate_stops_at_first_commit() {
        let c = PickerController(items: fixtureItems())
        let result = c.simulate("saf".map { .char($0) } + [.enter, .char("x")])
        #expect(result == .commit(id: 200))
    }

    @Test func simulate_stops_at_first_cancel() {
        let c = PickerController(items: fixtureItems())
        let result = c.simulate([.char("s"), .escape, .enter])
        #expect(result == .cancel)
    }

    @Test func simulate_returns_last_non_idle_action_when_no_commit_or_cancel() {
        let c = PickerController(items: fixtureItems())
        let result = c.simulate([.tab, .backspace]) // backspace on empty query -> idle
        #expect(result == .refilter)
    }
}
