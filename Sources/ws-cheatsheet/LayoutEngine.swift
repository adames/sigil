import AppKit

// MARK: - Adaptive layout engine
//
// The HUD is a borderless overlay locked to `screen.visibleFrame` (see
// main.swift). The window CANNOT grow to fit content — that was the old
// "disappeared after 1-2s" off-screen-growth bug. So the *content* adapts
// to the *frame*, on two independent axes:
//
//   WIDTH  → how many columns, and how wide.
//   HEIGHT → which typographic tier (font + padding sizes).
//
// Everything here is closed-form arithmetic over row counts and text
// measurement (`NSAttributedString.boundingRect`, a pure text-only Core
// Text call — no view tree, no intrinsic size that could grow the
// window). The planner runs synchronously inside the existing
// `GeometryReader`, whose `geo.size` is already bounded by the fixed host
// container. Nothing here ever reads SwiftUI's `fittingSize`.
//
// Why a ladder of real tiers instead of one design scaled with
// `.scaleEffect`: real per-tier fonts stay crisp on large monitors and at
// every Retina scaling, where an upscaled bitmap would soften.

/// One typographic density tier. `.spacious` is the original hand-tuned
/// look (kept byte-for-byte) and the top rung; denser rungs shrink fonts
/// AND padding (vertical padding is the silent height driver, so it has to
/// scale too) so the densest lens still fits a short display.
struct LayoutMetrics {
    let titleSize: CGFloat
    let subSize: CGFloat
    let ideaSize: CGFloat
    let rowDescSize: CGFloat
    let keyCapSize: CGFloat
    let badgeSize: CGFloat
    let rowVerticalPadding: CGFloat
    let cardHPadding: CGFloat
    let cardVPadding: CGFloat
    let cardSpacing: CGFloat
    let columnSpacing: CGFloat

    static let spacious = LayoutMetrics(
        titleSize: 22, subSize: 14, ideaSize: 16, rowDescSize: 17,
        keyCapSize: 16, badgeSize: 8, rowVerticalPadding: 3,
        cardHPadding: 18, cardVPadding: 10, cardSpacing: 10, columnSpacing: 16
    )
    static let comfortable = LayoutMetrics(
        titleSize: 20, subSize: 13, ideaSize: 14.5, rowDescSize: 15,
        keyCapSize: 14, badgeSize: 7.5, rowVerticalPadding: 2.5,
        cardHPadding: 16, cardVPadding: 9, cardSpacing: 9, columnSpacing: 14
    )
    static let cozy = LayoutMetrics(
        titleSize: 18, subSize: 12, ideaSize: 13, rowDescSize: 13.5,
        keyCapSize: 12.5, badgeSize: 7, rowVerticalPadding: 2,
        cardHPadding: 14, cardVPadding: 8, cardSpacing: 8, columnSpacing: 12
    )
    static let compact = LayoutMetrics(
        titleSize: 16, subSize: 11, ideaSize: 12, rowDescSize: 12.5,
        keyCapSize: 11.5, badgeSize: 6.5, rowVerticalPadding: 1.5,
        cardHPadding: 12, cardVPadding: 7, cardSpacing: 7, columnSpacing: 10
    )
    // Floor tier for heavily-zoomed small laptops ("Larger Text" scaling,
    // visibleFrame as short as ~600pt). Small but still legible; chosen only
    // when nothing looser fits.
    static let tight = LayoutMetrics(
        titleSize: 14, subSize: 10, ideaSize: 11, rowDescSize: 11.5,
        keyCapSize: 10.5, badgeSize: 6, rowVerticalPadding: 1,
        cardHPadding: 11, cardVPadding: 6, cardSpacing: 6, columnSpacing: 9
    )

    /// Loosest → densest. The planner walks this and renders at the
    /// loosest tier whose tallest column fits the available height.
    static let ladder: [LayoutMetrics] = [.spacious, .comfortable, .cozy, .compact, .tight]
}

/// The renderer-facing result: which tier, the sections grouped into
/// display columns, the per-column width, and a last-resort scroll flag.
struct LayoutPlan {
    let metrics: LayoutMetrics
    let columns: [[CheatsheetDocument.Section]]
    let columnWidth: CGFloat
    /// True when a tier was found whose tallest column fits the height.
    /// False only when even the densest tier overflows (a pathologically
    /// small display) — the renderer then top-aligns so the top rows stay
    /// visible (graceful bottom-clip) instead of centering and clipping
    /// both ends. Normal displays always fit.
    let fits: Bool
}

enum CheatsheetLayout {
    // Card sizing band. `target` governs how many columns we *aim* for
    // (kept a touch above `maxWidth` so laptops settle on 2 wide columns
    // and only genuinely wide displays earn a 3rd/4th); `maxWidth` caps how
    // wide a card may actually get (so a 2-section lens on a 5K display is
    // a calm centered pair, not two giant ribbons); `minWidth` is the
    // cramped floor (drop a column rather than go narrower).
    static let columnTargetWidth: CGFloat = 600
    static let columnMaxWidth: CGFloat = 560
    static let columnMinWidth: CGFloat = 300
    // Hard cap on columns. With 2-4 sections per lens, more than 3 columns
    // just fans the sections out into uneven single-section strips on wide
    // displays (the very "unevenness" we're fixing). Capping keeps adjacent
    // sections merging into balanced columns instead.
    static let maxColumns: Int = 3
    /// Headroom kept under the measured available height so a few px of
    /// estimator slack never clips the bottom row.
    static let heightSafetyMargin: CGFloat = 10

    /// Plan the layout for a lens's ordered sections within the available
    /// space. `availableWidth`/`availableHeight` come straight from the
    /// columnGrid GeometryReader.
    static func plan(
        for ordered: [CheatsheetDocument.Section],
        availableWidth: CGFloat,
        availableHeight: CGFloat
    ) -> LayoutPlan {
        guard !ordered.isEmpty, availableWidth > 0 else {
            return LayoutPlan(metrics: .spacious, columns: [], columnWidth: 0, fits: true)
        }

        let budget = availableHeight - heightSafetyMargin

        // Walk tiers loosest → densest; take the first whose tallest column
        // fits the height budget. This forces a denser tier only where the
        // display actually demands it (short / "Larger Text" laptops), and
        // leaves big displays on `.spacious`.
        for metrics in LayoutMetrics.ladder {
            let arranged = arrange(ordered, metrics: metrics, availableWidth: availableWidth)
            if arranged.tallest <= budget {
                return LayoutPlan(
                    metrics: metrics,
                    columns: arranged.columns,
                    columnWidth: arranged.columnWidth,
                    fits: true
                )
            }
        }

        // Nothing fits even at the densest tier (a tiny, heavily-zoomed
        // display). Render densest, top-aligned, accepting a bottom-edge
        // clip. Not reached on real displays at default scaling.
        let metrics = LayoutMetrics.ladder.last!
        let arranged = arrange(ordered, metrics: metrics, availableWidth: availableWidth)
        return LayoutPlan(
            metrics: metrics,
            columns: arranged.columns,
            columnWidth: arranged.columnWidth,
            fits: false
        )
    }

    // MARK: Column count + balanced distribution

    /// For a fixed tier: choose a column count from the width, then balance
    /// the ordered sections into that many columns by estimated height.
    private static func arrange(
        _ ordered: [CheatsheetDocument.Section],
        metrics: LayoutMetrics,
        availableWidth: CGFloat
    ) -> (columns: [[CheatsheetDocument.Section]], columnWidth: CGFloat, tallest: CGFloat) {
        let n = ordered.count
        let spacing = metrics.columnSpacing

        // Aim for one column per `columnTargetWidth` of width, never more
        // than the number of sections (this single clamp is what
        // structurally kills the stranded empty column).
        var cols = Int(((availableWidth + spacing) / (columnTargetWidth + spacing)).rounded())
        cols = max(1, min(cols, min(n, maxColumns)))
        // Back off if cards would be cramped below the min width.
        while cols > 1, (availableWidth - spacing * CGFloat(cols - 1)) / CGFloat(cols) < columnMinWidth {
            cols -= 1
        }

        let columnWidth = min((availableWidth - spacing * CGFloat(cols - 1)) / CGFloat(cols), columnMaxWidth)

        let heights = ordered.map { estimateSectionHeight($0, metrics: metrics, columnWidth: columnWidth) }
        let groups = balancedGroups(heights, into: cols, gap: metrics.cardSpacing)

        let columns = groups.map { range in Array(ordered[range]) }
        let tallest = groups.map { columnHeight(heights, range: $0, gap: metrics.cardSpacing) }.max() ?? 0
        return (columns, columnWidth, tallest)
    }

    /// Total height of one column (sum of its cards + inter-card spacing).
    private static func columnHeight(_ heights: [CGFloat], range: Range<Int>, gap: CGFloat) -> CGFloat {
        guard !range.isEmpty else { return 0 }
        let sum = heights[range].reduce(0, +)
        return sum + gap * CGFloat(range.count - 1)
    }

    /// Partition the ordered sections into `k` CONTIGUOUS groups (reading
    /// order preserved) that minimize the tallest column — the classic
    /// linear-partition / "painter's" objective. With only 2-4 sections per
    /// lens this is a tiny DP. When `k == n` it degenerates to one section
    /// per column; when `k < n` adjacent short sections merge to even the
    /// columns out (this is what fixes the per-machine unevenness).
    static func balancedGroups(_ heights: [CGFloat], into k: Int, gap: CGFloat) -> [Range<Int>] {
        let n = heights.count
        if n == 0 { return [] }
        let k = max(1, min(k, n))
        if k == 1 { return [0..<n] }
        if k >= n { return (0..<n).map { $0..<($0 + 1) } }

        // dp[i][j] = min achievable tallest-column when partitioning
        // sections i..<n into j columns. choice[i][j] = chosen first cut.
        let big = CGFloat.greatestFiniteMagnitude
        var dp = Array(repeating: Array(repeating: big, count: k + 1), count: n + 1)
        var choice = Array(repeating: Array(repeating: n, count: k + 1), count: n + 1)
        dp[n][0] = 0
        for i in stride(from: n, through: 0, by: -1) {
            for j in 1...k where n - i >= j {       // need at least j sections left
                // First column takes i..<m, remaining j-1 columns take m..<n.
                let maxM = n - (j - 1)              // leave one per remaining column
                if i < maxM {
                    for m in (i + 1)...maxM {
                        let first = columnHeight(heights, range: i..<m, gap: gap)
                        let rest = dp[m][j - 1]
                        let worst = max(first, rest)
                        if worst < dp[i][j] {
                            dp[i][j] = worst
                            choice[i][j] = m
                        }
                    }
                }
            }
        }

        var ranges: [Range<Int>] = []
        var i = 0
        var j = k
        while j > 0 {
            let m = choice[i][j]
            ranges.append(i..<m)
            i = m
            j -= 1
        }
        return ranges
    }

    // MARK: Height estimation
    //
    // Mirrors SectionCard's structure field-for-field. Conservative
    // (rounds up; assumes desc text can wrap) so the chosen tier never
    // clips. Text heights come from real Core Text measurement at the same
    // fonts SwiftUI uses, so wrapping of long `idea`/desc strings is
    // accounted for rather than guessed.

    static func estimateSectionHeight(
        _ section: CheatsheetDocument.Section,
        metrics m: LayoutMetrics,
        columnWidth: CGFloat
    ) -> CGFloat {
        let usable = max(columnWidth - 2 * m.cardHPadding, 1)
        var h = 2 * m.cardVPadding

        // Title (uppercased, semibold, tracking 0.7 — see SectionCard) —
        // padding.bottom 2.
        h += textHeight(section.title.uppercased(), size: m.titleSize, weight: .semibold, tracking: 0.7, width: usable) + 2

        if let sub = section.sub, !sub.isEmpty {
            h += textHeight(sub, size: m.subSize, width: usable)
            h += (section.idea == nil ? 8 : 4)
        }
        if let idea = section.idea, !idea.isEmpty {
            h += textHeight(idea, size: m.ideaSize, italic: true, width: usable) + 8
        }
        if section.customLayout?.lowercased() == "keyboard" {
            // SpatialKeyboardView is a fixed-size diagram (3 cap rows +
            // legend ≈ 110pt). Flat constant with headroom so the estimate
            // stays conservative at every tier. Latent: no shipped section
            // sets customLayout == "keyboard".
            h += 120 + (section.rows.isEmpty ? 0 : 10)
        }

        for row in section.rows {
            h += rowHeight(row, metrics: m, usable: usable)
        }
        return ceil(h)
    }

    /// Height of one key/desc row — `max(keycap, wrapped desc)` plus the
    /// row's vertical padding. Footnote rows (`key == "—"`) are italic
    /// prose with a fixed 60pt lead column.
    private static func rowHeight(_ row: [String], metrics m: LayoutMetrics, usable: CGFloat) -> CGFloat {
        let key = row.indices.contains(0) ? row[0] : ""
        let desc = row.indices.contains(1) ? row[1] : ""
        let rowPad = 2 * m.rowVerticalPadding

        if key == "—" {
            // Footnote HStack(spacing: 8): "—".frame(width: 60) · desc · Spacer
            // → 60pt lead + two 8pt gaps.
            let descWidth = max(usable - 60 - 16, 40)
            let descH = textHeight(desc, size: m.rowDescSize - 1, italic: true, width: descWidth)
            let keyH = lineHeight(size: m.rowDescSize, monospaced: true)
            return max(descH, keyH) + rowPad
        }

        // HStack(spacing: 8): badge · keycap · desc · Spacer → three 8pt
        // gaps. Keycap is fixed-size monospaced; desc wraps in the width
        // that remains. (Under-counting these gaps would over-state desc
        // width and under-estimate height — the one direction that clips.)
        let keyCapWidth = textWidth(key, size: m.keyCapSize, monospaced: true) + 12
        let descWidth = max(usable - m.badgeSize - keyCapWidth - 24, 40)
        let descH = textHeight(desc, size: m.rowDescSize, width: descWidth)
        let keyCapH = lineHeight(size: m.keyCapSize, monospaced: true) + 4   // KeyCap vertical padding 2*2
        return max(keyCapH, descH) + rowPad
    }

    // MARK: Core Text measurement (pure, no view tree)

    private static func font(_ size: CGFloat, weight: NSFont.Weight, monospaced: Bool, italic: Bool) -> NSFont {
        var f = monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        if italic {
            f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask)
        }
        return f
    }

    private static func lineHeight(size: CGFloat, weight: NSFont.Weight = .regular, monospaced: Bool = false) -> CGFloat {
        let f = font(size, weight: weight, monospaced: monospaced, italic: false)
        return ceil(f.ascender - f.descender + f.leading)
    }

    private static func textWidth(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular, monospaced: Bool = false) -> CGFloat {
        guard !s.isEmpty else { return 0 }
        let f = font(size, weight: weight, monospaced: monospaced, italic: false)
        return ceil(NSAttributedString(string: s, attributes: [.font: f]).size().width)
    }

    /// Wrapped height of a string in a fixed-width box, at the same font
    /// SwiftUI renders. Single-line strings collapse to one line height.
    private static func textHeight(
        _ s: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        monospaced: Bool = false,
        italic: Bool = false,
        tracking: CGFloat = 0,
        width: CGFloat
    ) -> CGFloat {
        guard !s.isEmpty else { return 0 }
        let f = font(size, weight: weight, monospaced: monospaced, italic: italic)
        var attrs: [NSAttributedString.Key: Any] = [.font: f]
        if tracking != 0 { attrs[.kern] = tracking }   // mirrors SwiftUI .tracking
        let rect = NSAttributedString(string: s, attributes: attrs).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height)
    }
}
