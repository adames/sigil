import SwiftUI
import WsUI   // re-exports `Color(hex:)`

/// HUD view, a learning aid shaped as a multi-lens mosaic.
///
/// - Each **lens** is one named view over the section pool — declared in
///   `cheatsheet.json` under `views[]`. The user toggles between lenses
///   via number keys (1..N) or Tab inside the HUD.
/// - Each **column** of the active lens stacks cards top-down. Card
///   layout is declared by the lens; no algorithm.
/// - **Family colors** (system blue, terminal green, vim peach, nvim
///   mauve) carry the categorical cue. Sections share a family.
/// - Window position uses `screen.visibleFrame` so the HUD sits cleanly
///   below the menu bar and above the Dock.
struct CheatsheetView: View {
    @ObservedObject var state: CheatsheetState
    let timestamp: String

    private let outerHPadding: CGFloat = 20
    /// Small margin below the menu bar. The window is positioned via
    /// `screen.visibleFrame` so it already sits below the menu strip;
    /// this is just enough to keep the banner from feeling pinned to
    /// the boundary without eating row budget.
    private let outerTopPadding: CGFloat = 12
    private let outerBottomPadding: CGFloat = 12

    private var document: CheatsheetDocument { state.document }
    private var currentLens: CheatsheetDocument.Lens { state.currentLens }
    private var resolvedColumns: [CheatsheetDocument.ResolvedColumn] {
        document.resolve(view: currentLens)
    }
    private var metrics: LayoutMetrics { .spacious }

    var body: some View {
        VStack(spacing: 12) {
            bannerStrip
            lensPicker
            columnGrid
            footer
        }
        .padding(.horizontal, outerHPadding)
        .padding(.top, outerTopPadding)
        .padding(.bottom, outerBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            // Solid scrim instead of a live behind-window blur: one
            // alpha-composited fill paints on the first frame (the blur
            // sampled the whole desktop every frame, which is what made the
            // HUD "show up weird"). The faint translucency still separates
            // the cards from the desktop without the GPU cost.
            Palette.resolved.crust.opacity(0.92)
                .ignoresSafeArea()
        )
    }

    /// Columns of the active lens, horizontally centered.
    ///
    /// Each visible column claims the same width it would have if every
    /// declared column were filled — that is, `(width - 2·spacing) / 3`.
    /// Empty columns are dropped; the remaining ones collapse the HStack
    /// to its natural width, and the outer frame's `.top` alignment
    /// centers it horizontally (and tops it vertically). The end result:
    /// lenses with one empty column (AeroSpace / Terminal / Vim) shift
    /// to the middle of the screen instead of left-justifying with a
    /// dead right column.
    private var columnGrid: some View {
        GeometryReader { geo in
            let totalCols = resolvedColumns.count
            let spacing = metrics.columnSpacing
            let colWidth: CGFloat = totalCols > 0
                ? max((geo.size.width - spacing * CGFloat(totalCols - 1)) / CGFloat(totalCols), 0)
                : 0
            let visible = resolvedColumns.filter { !$0.sections.isEmpty }

            HStack(alignment: .top, spacing: spacing) {
                ForEach(visible) { column in
                    VStack(spacing: metrics.cardSpacing) {
                        ForEach(column.sections) { section in
                            SectionCard(section: section, metrics: metrics)
                        }
                    }
                    .frame(width: colWidth, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Banner (legend for the modifier badges below)

    private var bannerStrip: some View {
        HStack(spacing: 22) {
            ForEach(Array(document.banner.enumerated()), id: \.offset) { idx, item in
                HStack(spacing: 8) {
                    ModifierBadge(forChord: item.k)
                    KeyCap(text: item.k)
                    Text(item.v)
                        .font(.system(size: 9))
                        .foregroundColor(Palette.resolved.subtext0)
                        .lineLimit(1)
                }
                if idx < document.banner.count - 1 {
                    Text("·").foregroundColor(Palette.resolved.surface2)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 999)
                .fill(Palette.resolved.mantle.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .strokeBorder(Palette.resolved.surface0.opacity(0.6), lineWidth: 1)
                )
        )
    }

    // MARK: - Lens picker

    /// Row of chips, one per lens. Active chip is highlighted in the
    /// dominant family color (best-guess: family of the first
    /// non-aerospace section in the lens, else the lens's first
    /// section's family, else system blue).
    private var lensPicker: some View {
        HStack(spacing: 8) {
            ForEach(Array(document.views.enumerated()), id: \.element.id) { idx, lens in
                lensChip(lens: lens, isActive: idx == state.currentIndex)
            }
        }
    }

    private func lensChip(lens: CheatsheetDocument.Lens, isActive: Bool) -> some View {
        let accent = chipAccent(for: lens)
        return HStack(spacing: 6) {
            Text(lens.key)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? Palette.resolved.crust : accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isActive ? accent : accent.opacity(0.16))
                )
            Text(lens.label)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? accent : Palette.resolved.subtext0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 999)
                .fill(isActive
                      ? accent.opacity(0.12)
                      : Palette.resolved.mantle.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .strokeBorder(
                            isActive ? accent.opacity(0.55) : Palette.resolved.surface0.opacity(0.55),
                            lineWidth: 1
                        )
                )
        )
    }

    /// A lens's chip-accent: scan its columns for the first section
    /// whose family isn't `system`; use that family's color. If every
    /// section is system (the AeroSpace lens), use system blue. Falls
    /// through to system blue for empty / unknown lenses.
    private func chipAccent(for lens: CheatsheetDocument.Lens) -> Color {
        for column in lens.columns {
            for id in column.sections {
                guard let section = document.sections[id] else { continue }
                if let family = section.family, family != "system",
                   let color = FamilyColors.color(forFamily: family) {
                    return color
                }
            }
        }
        return FamilyColors.system
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            // Two emphasis steps: legible key legend + a fainter timestamp,
            // both kept above the 4.5:1 contrast floor (was 9pt overlay0).
            Text("1–\(document.views.count) switch lens  ·  tab cycle  ·  esc or caps+/ closes")
                .foregroundColor(Palette.resolved.hint)
            + Text("  ·  \(timestamp)")
                .foregroundColor(Palette.resolved.faintHint)
        }
        .font(.system(size: 11))
        .tracking(0.4)
    }
}

// MARK: - LayoutMetrics
//
// Single tier sized for ≤ 4 sections per lens — large enough to read
// at a glance, tight enough on vertical padding that AeroSpace's
// densest column (14 rows + a long idea wrap) fits inside the
// visibleFrame on a standard MacBook display.
//
// If a future lens lands with more sections than `spacious` can hold,
// reintroduce a `compact` tier here and have the view pick between
// them based on section count.

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
        titleSize: 22,
        subSize: 14,
        ideaSize: 16,
        rowDescSize: 17,
        keyCapSize: 16,
        badgeSize: 8,
        rowVerticalPadding: 3,
        cardHPadding: 18,
        cardVPadding: 10,
        cardSpacing: 10,
        columnSpacing: 16
    )
}

// MARK: - SectionCard

private struct SectionCard: View {
    let section: CheatsheetDocument.Section
    let metrics: LayoutMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(section.title.uppercased())
                    .font(.system(size: metrics.titleSize, weight: .semibold))
                    .tracking(0.7)
                    .foregroundColor(accentColor)
                    .padding(.bottom, 2)

                if let sub = section.sub, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: metrics.subSize))
                        .foregroundColor(Palette.resolved.overlay1)
                        .padding(.bottom, section.idea == nil ? 8 : 4)
                }

                if let idea = section.idea, !idea.isEmpty {
                    Text(idea)
                        .font(.system(size: metrics.ideaSize))
                        .italic()
                        .foregroundColor(accentColor.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)
                }

                // Custom-layout sections (currently only "keyboard") render
                // a diagram above the row table.
                if section.customLayout?.lowercased() == "keyboard" {
                    SpatialKeyboardView()
                        .padding(.bottom, section.rows.isEmpty ? 0 : 10)
                }

                ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                    rowView(row)
                }
            }
            .padding(.horizontal, metrics.cardHPadding)
            .padding(.top, metrics.cardVPadding)
            .padding(.bottom, metrics.cardVPadding)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.resolved.mantle.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(accentColor.opacity(0.22), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func rowView(_ row: [String]) -> some View {
        let key = row.indices.contains(0) ? row[0] : ""
        let desc = row.indices.contains(1) ? row[1] : ""

        return HStack(alignment: .top, spacing: 8) {
            if key == "—" {
                // Footnote row: italic muted prose, no badge, no keycap.
                Text("—")
                    .font(.system(size: metrics.rowDescSize, design: .monospaced))
                    .foregroundColor(Palette.resolved.surface2)
                    .frame(width: 60, alignment: .leading)
                Text(desc)
                    .font(.system(size: metrics.rowDescSize - 1))
                    .foregroundColor(Palette.resolved.overlay0)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ModifierBadge(forChord: key, size: metrics.badgeSize)
                    .padding(.top, 4)
                KeyCap(text: key, fontSize: metrics.keyCapSize)
                    .layoutPriority(1)
                Text(desc)
                    .font(.system(size: metrics.rowDescSize))
                    .foregroundColor(Palette.resolved.subtext0)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, metrics.rowVerticalPadding)
    }

    private var accentColor: Color {
        FamilyColors.resolve(family: section.family, fallbackHex: section.color ?? "")
    }
}

// MARK: - KeyCap

/// Visual rendering of a key chord. Looks like a keycap with a faint border.
/// `fontSize` defaults to the compact metric so banner / lens-chip uses
/// keep their fixed size; section rows pass the active metric's size.
struct KeyCap: View {
    let text: String
    var fontSize: CGFloat = 10

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundColor(Palette.resolved.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Palette.resolved.surface0.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Palette.resolved.surface1, lineWidth: 1)
                    )
            )
            .fixedSize(horizontal: true, vertical: false)
    }
}
