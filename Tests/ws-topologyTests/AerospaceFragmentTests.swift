import AerospaceEmit
import Foundation
import Testing

@Suite("AerospaceFragment.merge — sentinel-fenced block writer")
struct AerospaceFragmentMergeTests {

    @Test func append_to_empty_file() throws {
        let merged = try AerospaceFragment.merge(
            block: "# >>> sigil generated >>>\n[mode.main.binding]\n# <<< sigil generated <<<\n",
            into: ""
        )
        #expect(merged.hasPrefix("# >>> sigil generated >>>"))
        #expect(merged.contains("[mode.main.binding]"))
        #expect(merged.hasSuffix("# <<< sigil generated <<<\n"))
    }

    @Test func append_to_user_owned_toml_with_no_fence() throws {
        let existing = """
        gaps.outer.top = 26

        [workspace-to-monitor-force-assignment]
        "1" = 1
        "2" = 1
        """
        let block = """
        # >>> sigil generated >>>
        [mode.main.binding]
        cmd-alt-ctrl-shift-1 = 'workspace 1'
        # <<< sigil generated <<<
        """
        let merged = try AerospaceFragment.merge(block: block, into: existing)
        // User content preserved verbatim
        #expect(merged.contains("gaps.outer.top = 26"))
        #expect(merged.contains(#""1" = 1"#))
        // Fence appended at the end with a separator newline
        #expect(merged.contains("# >>> sigil generated >>>"))
        #expect(merged.range(of: "# >>> sigil generated >>>")!.lowerBound >
                merged.range(of: "[workspace-to-monitor-force-assignment]")!.lowerBound)
    }

    @Test func replace_existing_fenced_block_in_place() throws {
        let existing = """
        gaps.outer.top = 26

        # >>> sigil generated >>>
        OLD BLOCK CONTENT
        TO BE REPLACED
        # <<< sigil generated <<<

        [extra-user-section]
        key = "value"
        """
        let block = """
        # >>> sigil generated >>>
        NEW BLOCK CONTENT
        # <<< sigil generated <<<
        """
        let merged = try AerospaceFragment.merge(block: block, into: existing)
        #expect(!merged.contains("OLD BLOCK CONTENT"))
        #expect(!merged.contains("TO BE REPLACED"))
        #expect(merged.contains("NEW BLOCK CONTENT"))
        // User content above and below the fence survives intact
        #expect(merged.contains("gaps.outer.top = 26"))
        #expect(merged.contains("[extra-user-section]"))
        #expect(merged.contains(#"key = "value""#))
    }

    @Test func idempotent_under_repeated_merge() throws {
        let existing = """
        # >>> sigil generated >>>
        cmd-alt-ctrl-shift-1 = 'workspace 1'
        # <<< sigil generated <<<
        """
        let block = """
        # >>> sigil generated >>>
        cmd-alt-ctrl-shift-1 = 'workspace 1'
        # <<< sigil generated <<<
        """
        let once  = try AerospaceFragment.merge(block: block, into: existing)
        let twice = try AerospaceFragment.merge(block: block, into: once)
        #expect(once == twice, "double-merge should be a no-op")
    }

    @Test func append_separates_with_newline_when_existing_lacks_trailing_newline() throws {
        let existing = "gaps.outer.top = 26"   // no trailing \n
        let block = """
        # >>> sigil generated >>>
        x
        # <<< sigil generated <<<
        """
        let merged = try AerospaceFragment.merge(block: block, into: existing)
        // Should NOT smush "gaps.outer.top = 26# >>> sigil generated >>>"
        #expect(merged.contains("gaps.outer.top = 26\n# >>> sigil generated >>>"))
    }

    /// Regression: appending below an orphaned open fence used to pair
    /// the orphan with the appended block's close fence on the NEXT
    /// merge, clobbering every user line in between. The merge now
    /// refuses the damaged file instead.
    @Test func orphaned_open_fence_throws_instead_of_appending() {
        let existing = """
        # >>> sigil generated >>>
        old content whose close fence a hand-edit deleted

        [user-section]
        key = "value"
        """
        let block = """
        # >>> sigil generated >>>
        NEW
        # <<< sigil generated <<<
        """
        #expect(throws: AerospaceFragment.MergeError.unterminatedFence(
            open: AerospaceFragment.openFence
        )) {
            _ = try AerospaceFragment.merge(block: block, into: existing)
        }
    }

    /// The assignment fence uses a distinct fence pair so the merge can
    /// update the `[workspace-to-monitor-force-assignment]` block
    /// independently of the digit bindings. Verifies the parametrised
    /// merge writes into the right region and leaves the other untouched.
    @Test func assignment_fence_merges_independently_of_bindings_fence() throws {
        let existing = """
        # >>> sigil generated: assignments >>>
        OLD ASSIGN
        # <<< sigil generated: assignments <<<

        [mode.main.binding]
        # >>> sigil generated >>>
        OLD BINDINGS
        # <<< sigil generated <<<
        """
        let newAssign = """
        # >>> sigil generated: assignments >>>
        [workspace-to-monitor-force-assignment]
        "main" = 1
        # <<< sigil generated: assignments <<<
        """
        let merged = try AerospaceFragment.merge(
            block: newAssign,
            into: existing,
            openFence: AerospaceFragment.assignmentOpenFence,
            closeFence: AerospaceFragment.assignmentCloseFence
        )
        // Assignment region rewritten
        #expect(!merged.contains("OLD ASSIGN"))
        #expect(merged.contains(#""main" = 1"#))
        // Bindings region untouched
        #expect(merged.contains("OLD BINDINGS"))
        #expect(merged.contains("# >>> sigil generated >>>"))
    }

    /// Belt-and-braces: re-merging the same assignment block produces no
    /// change. Pins the idempotency contract for the second fence pair.
    @Test func assignment_fence_is_idempotent() throws {
        let existing = """
        # >>> sigil generated: assignments >>>
        [workspace-to-monitor-force-assignment]
        "main" = 1
        # <<< sigil generated: assignments <<<
        """
        let block = existing
        let once  = try AerospaceFragment.merge(
            block: block, into: existing,
            openFence: AerospaceFragment.assignmentOpenFence,
            closeFence: AerospaceFragment.assignmentCloseFence
        )
        let twice = try AerospaceFragment.merge(
            block: block, into: once,
            openFence: AerospaceFragment.assignmentOpenFence,
            closeFence: AerospaceFragment.assignmentCloseFence
        )
        #expect(once == twice, "double-merge of assignment block should be a no-op")
    }

    @Test func doc_comment_referencing_fence_by_name_is_ignored() throws {
        let existing = """
        # AeroSpace configuration
        #
        # This file replaces yabairc + skhdrc. The block between
        # `# >>> sigil generated >>>` and `# <<< sigil generated <<<` is
        # OWNED BY ws-topology. Hand-edits inside are clobbered.

        start-at-login = true

        [gaps]
        outer.top = 26

        [mode.main.binding]
        cmd-alt-ctrl-shift-h = 'focus left'

        # >>> sigil generated >>>
        # placeholder
        # <<< sigil generated <<<
        """
        let block = """
        # >>> sigil generated >>>
        NEW
        # <<< sigil generated <<<
        """
        let merged = try AerospaceFragment.merge(block: block, into: existing)
        // User content survives. The substring "# >>> sigil generated >>>"
        // appears TWICE in the doc comment + once at the real fence open;
        // only the real fence open should be matched.
        #expect(merged.contains("This file replaces yabairc"),
                "doc comment must survive — the substring match used to clobber this")
        #expect(merged.contains("start-at-login = true"))
        #expect(merged.contains("[gaps]"))
        #expect(merged.contains("cmd-alt-ctrl-shift-h = 'focus left'"))
        #expect(merged.contains("NEW"))
        #expect(!merged.contains("# placeholder"),
                "real fenced placeholder block should be replaced")
    }
}

@Suite("AerospaceFragment.render — generated TOML stays parseable")
struct AerospaceFragmentRenderTests {

    @Test func bindings_render_digits_with_slot_ten_as_zero() {
        let names = (1...10).map(String.init) + ["overflow"]
        let block = AerospaceFragment.render(slotNames: names)
        #expect(block.contains(#"cmd-alt-ctrl-shift-1 = "workspace 1""#))
        #expect(block.contains(#"cmd-alt-ctrl-shift-9 = "workspace 9""#))
        #expect(block.contains(#"cmd-alt-ctrl-shift-0 = "workspace 10""#))
        #expect(!block.contains("overflow"), "only the first 10 slots get digit chords")
    }

    @Test func assignment_block_pins_every_slot() {
        let block = AerospaceFragment.renderAssignmentBlock(slotNames: ["code", "web"])
        #expect(block.contains("[workspace-to-monitor-force-assignment]"))
        #expect(block.contains(#""code" = 1"#))
        #expect(block.contains(#""web" = 1"#))
    }

    @Test func empty_slot_list_renders_placeholder_comment_only() {
        let bindings = AerospaceFragment.render(slotNames: [])
        let assigns  = AerospaceFragment.renderAssignmentBlock(slotNames: [])
        #expect(bindings.contains("# (no workspaces declared in spaces.json yet)"))
        #expect(!assigns.contains("[workspace-to-monitor-force-assignment]"),
                "an empty table header would still claim the table name")
    }

    /// Regression: the old renderer emitted `'workspace name'` literal
    /// strings with a fake `\'` escape — TOML literal strings support no
    /// escapes, so an apostrophe in a workspace name corrupted the file.
    /// Names now render as basic strings with real escaping.
    @Test func quote_bearing_names_stay_within_their_string() {
        let bindings = AerospaceFragment.render(slotNames: [#"it's"#, #"say "hi""#])
        #expect(bindings.contains(#"cmd-alt-ctrl-shift-1 = "workspace it's""#))
        #expect(bindings.contains(#"cmd-alt-ctrl-shift-2 = "workspace say \"hi\"""#))

        let assigns = AerospaceFragment.renderAssignmentBlock(slotNames: [#"say "hi""#])
        #expect(assigns.contains(#""say \"hi\"" = 1"#))
    }

    @Test func toml_basic_string_escaping() {
        #expect(AerospaceFragment.escapeTOMLBasicString("plain") == "plain")
        #expect(AerospaceFragment.escapeTOMLBasicString(#"a"b"#) == #"a\"b"#)
        #expect(AerospaceFragment.escapeTOMLBasicString(#"a\b"#) == #"a\\b"#)
        #expect(AerospaceFragment.escapeTOMLBasicString("a\nb") == #"a\nb"#)
        #expect(AerospaceFragment.escapeTOMLBasicString("a\u{01}b") == #"a\u0001b"#)
    }
}
