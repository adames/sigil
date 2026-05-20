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

    /// Verbatim copy of `AerospaceFragment.merge` semantics — replaces the
    /// fenced block in-place, or appends with a separator newline when the
    /// fence is absent.
    static func merge(block: String, into existing: String) -> String {
        let cleanBlock = block.hasSuffix("\n") ? String(block.dropLast()) : block

        guard let openRange = existing.range(of: openFence),
              let closeRange = existing.range(of: closeFence,
                                              range: openRange.upperBound..<existing.endIndex)
        else {
            let needsSeparator = !existing.isEmpty && !existing.hasSuffix("\n")
            return existing + (needsSeparator ? "\n" : "") + cleanBlock + "\n"
        }

        let afterClose = existing.index(closeRange.upperBound, offsetBy: 0)
        var replaceUpper = closeRange.upperBound
        if afterClose < existing.endIndex, existing[afterClose] == "\n" {
            replaceUpper = existing.index(after: afterClose)
        }
        return existing.replacingCharacters(
            in: openRange.lowerBound..<replaceUpper,
            with: cleanBlock + "\n"
        )
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
}
