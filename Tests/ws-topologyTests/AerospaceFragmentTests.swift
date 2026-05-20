import Foundation
import Testing

// `AerospaceFragment` lives inside the ws-topology executable target, not a
// library — it's not importable directly. Mirror its small public surface
// here as a test-local copy. The merge / render logic is pure-function, so
// the duplication is structural-only: keep this file in lockstep with the
// AerospaceFragment enum in Sources/ws-topology/main.swift.
//
// (Phase 4: ws-topology emits aerospace.toml block.)
enum FragmentMirror {
    static let openFence  = "# >>> sigil generated >>>"
    static let closeFence = "# <<< sigil generated <<<"

    static let assignmentOpenFence  = "# >>> sigil generated: assignments >>>"
    static let assignmentCloseFence = "# <<< sigil generated: assignments <<<"

    /// Verbatim copy of `AerospaceFragment.merge` semantics — replaces the
    /// fenced block in-place (line-anchored: fence must be a standalone
    /// line, not a substring inside a doc comment), or appends with a
    /// separator newline when the fence is absent. Fence pair is
    /// parameterised so the same engine handles either the digit-bindings
    /// region or the workspace-assignments region.
    static func merge(
        block: String,
        into existing: String,
        openFence: String = FragmentMirror.openFence,
        closeFence: String = FragmentMirror.closeFence
    ) -> String {
        let cleanBlock = block.hasSuffix("\n") ? String(block.dropLast()) : block

        var lines = existing.components(separatedBy: "\n")
        let hadTrailingNewline = existing.hasSuffix("\n")
        if hadTrailingNewline, lines.last == "" { lines.removeLast() }

        let openIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == openFence })
        let closeIdx: Int? = openIdx.flatMap { o in
            lines[(o + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == closeFence })
        }

        if let o = openIdx, let c = closeIdx {
            let blockLines = cleanBlock.components(separatedBy: "\n")
            lines.replaceSubrange(o...c, with: blockLines)
            var out = lines.joined(separator: "\n")
            if hadTrailingNewline || !out.hasSuffix("\n") { out += "\n" }
            return out
        }

        let needsSeparator = !existing.isEmpty && !existing.hasSuffix("\n")
        return existing + (needsSeparator ? "\n" : "") + cleanBlock + "\n"
    }
}

@Suite("AerospaceFragment.merge — sentinel-fenced block writer")
struct AerospaceFragmentMergeTests {

    @Test func append_to_empty_file() {
        let merged = FragmentMirror.merge(
            block: "# >>> sigil generated >>>\n[mode.main.binding]\n# <<< sigil generated <<<\n",
            into: ""
        )
        #expect(merged.hasPrefix("# >>> sigil generated >>>"))
        #expect(merged.contains("[mode.main.binding]"))
        #expect(merged.hasSuffix("# <<< sigil generated <<<\n"))
    }

    @Test func append_to_user_owned_toml_with_no_fence() {
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
        let merged = FragmentMirror.merge(block: block, into: existing)
        // User content preserved verbatim
        #expect(merged.contains("gaps.outer.top = 26"))
        #expect(merged.contains(#""1" = 1"#))
        // Fence appended at the end with a separator newline
        #expect(merged.contains("# >>> sigil generated >>>"))
        #expect(merged.range(of: "# >>> sigil generated >>>")!.lowerBound >
                merged.range(of: "[workspace-to-monitor-force-assignment]")!.lowerBound)
    }

    @Test func replace_existing_fenced_block_in_place() {
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
        let merged = FragmentMirror.merge(block: block, into: existing)
        #expect(!merged.contains("OLD BLOCK CONTENT"))
        #expect(!merged.contains("TO BE REPLACED"))
        #expect(merged.contains("NEW BLOCK CONTENT"))
        // User content above and below the fence survives intact
        #expect(merged.contains("gaps.outer.top = 26"))
        #expect(merged.contains("[extra-user-section]"))
        #expect(merged.contains(#"key = "value""#))
    }

    @Test func idempotent_under_repeated_merge() {
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
        let once  = FragmentMirror.merge(block: block, into: existing)
        let twice = FragmentMirror.merge(block: block, into: once)
        #expect(once == twice, "double-merge should be a no-op")
    }

    @Test func append_separates_with_newline_when_existing_lacks_trailing_newline() {
        let existing = "gaps.outer.top = 26"   // no trailing \n
        let block = """
        # >>> sigil generated >>>
        x
        # <<< sigil generated <<<
        """
        let merged = FragmentMirror.merge(block: block, into: existing)
        // Should NOT smush "gaps.outer.top = 26# >>> sigil generated >>>"
        #expect(merged.contains("gaps.outer.top = 26\n# >>> sigil generated >>>"))
    }

    /// Regression: the merge writer's prior substring-based search would
    /// snag any line that contained the fence string — including a header
    /// comment that documented the fence by name (e.g. `# The block
    /// between \`# >>> sigil generated >>>\` and \`# <<< sigil generated
    /// <<<\` is owned by sigil`). That misplaced match clobbered the
    /// entire file between the doc comment and the real bottom fence.
    /// The fix is line-anchored matching — fence must be a standalone
    /// line. This test pins that contract.
    /// The assignment fence uses a distinct fence pair so the merge can
    /// update the `[workspace-to-monitor-force-assignment]` block
    /// independently of the digit bindings. Verifies the parametrised
    /// merge writes into the right region and leaves the other untouched.
    @Test func assignment_fence_merges_independently_of_bindings_fence() {
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
        let merged = FragmentMirror.merge(
            block: newAssign,
            into: existing,
            openFence: FragmentMirror.assignmentOpenFence,
            closeFence: FragmentMirror.assignmentCloseFence
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
    @Test func assignment_fence_is_idempotent() {
        let existing = """
        # >>> sigil generated: assignments >>>
        [workspace-to-monitor-force-assignment]
        "main" = 1
        # <<< sigil generated: assignments <<<
        """
        let block = existing
        let once  = FragmentMirror.merge(
            block: block, into: existing,
            openFence: FragmentMirror.assignmentOpenFence,
            closeFence: FragmentMirror.assignmentCloseFence
        )
        let twice = FragmentMirror.merge(
            block: block, into: once,
            openFence: FragmentMirror.assignmentOpenFence,
            closeFence: FragmentMirror.assignmentCloseFence
        )
        #expect(once == twice, "double-merge of assignment block should be a no-op")
    }

    @Test func doc_comment_referencing_fence_by_name_is_ignored() {
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
        let merged = FragmentMirror.merge(block: block, into: existing)
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
