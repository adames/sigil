import SwiftUI
import WsUI   // re-exports `Color(hex:)`

/// HUD view, a learning aid shaped as a multi-lens mosaic.
///
/// - Each **lens** is one named view over the section pool — declared in
///   `cheatsheet.json` under `views[]`. The user toggles between lenses
///   via number keys (1..N) or Tab inside the HUD.
/// - Each **column** of the active lens stacks cards top-down. Card
///   layout is declared by the lens; no algorithm.
/// - **Family colors** (system blue, terminal green, vim orange) carry
///   the categorical cue. Sections share a family.
/// - **Typography scales with section count**: lenses with ≤ 4 sections
///   render with a `spacious` metric (~35% bigger). The `All` lens (8
///   sections) keeps the `compact` metric since every section has to
///   share vertical room.
struct CheatsheetView: View {
    @ObservedObject var state: CheatsheetState
    let timestamp: String

    private let outerHPadding: CGFloat = 20
    private let outerTopPadding: CGFloat = 20
    private let outerBottomPadding: CGFloat = 16

    private var document: CheatsheetDocument { state.document }
    private var currentLens: CheatsheetDocument.Lens { state.currentLens }
    private var resolvedColumns: [CheatsheetDocument.ResolvedColumn] {
        document.resolve(view: currentLens)
    }
    private var metrics: LayoutMetrics {
        LayoutMetrics.forLens(currentLens, in: document)
    }

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
                        .foregroundColor(.white.opacity(0.58))
                        .lineLimit(1)
                }
                if idx < document.banner.count - 1 {
                    Text("·").foregroundColor(.white.opacity(0.18))
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 999)
                .fill(Color(red: 0.031, green: 0.039, blue: 0.059).opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
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
                .foregroundColor(isActive ? Color.black.opacity(0.78) : accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isActive ? accent : accent.opacity(0.16))
                )
            Text(lens.label)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? accent : .white.opacity(0.55))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 999)
                .fill(isActive
                      ? accent.opacity(0.12)
                      : Color(red: 0.031, green: 0.039, blue: 0.059).opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .strokeBorder(
                            isActive ? accent.opacity(0.55) : Color.white.opacity(0.06),
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
            Text("1..4 SWITCH LENS  ·  TAB CYCLE  ·  ESC OR CAPS+/ TO CLOSE  ·  \(timestamp)")
                .font(.system(size: 9))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.25))
            Spacer()
        }
    }
}

// MARK: - LayoutMetrics
//
// Two density tiers. The renderer picks one per lens based on section
// count: lenses with ≤ 4 cards get `spacious`; the All-lens gets
// `compact` because it has to fit 8 cards.

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

    static let compact = LayoutMetrics(
        titleSize: 13,
        subSize: 9,
        ideaSize: 10,
        rowDescSize: 11,
        keyCapSize: 10,
        badgeSize: 5,
        rowVerticalPadding: 3,
        cardHPadding: 12,
        cardVPadding: 10,
        cardSpacing: 10,
        columnSpacing: 12
    )

    static let spacious = LayoutMetrics(
        titleSize: 18,
        subSize: 12,
        ideaSize: 13,
        rowDescSize: 14,
        keyCapSize: 13,
        badgeSize: 7,
        rowVerticalPadding: 5,
        cardHPadding: 16,
        cardVPadding: 14,
        cardSpacing: 14,
        columnSpacing: 14
    )

    /// Density rule: lenses with > 4 resolved sections fall back to
    /// `compact`; anything sparser gets `spacious` so the typography can
    /// breathe. Threshold is forgiving on purpose — small jumps in
    /// section count shouldn't flip density.
    static func forLens(_ lens: CheatsheetDocument.Lens, in document: CheatsheetDocument) -> LayoutMetrics {
        let sectionCount = lens.columns
            .flatMap { $0.sections }
            .filter { document.sections[$0] != nil }
            .count
        return sectionCount > 4 ? .compact : .spacious
    }
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
                        .foregroundColor(.white.opacity(0.38))
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
                .fill(Color(red: 0.031, green: 0.039, blue: 0.059).opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(accentColor.opacity(0.18), lineWidth: 1)
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
                    .foregroundColor(.white.opacity(0.22))
                    .frame(width: 60, alignment: .leading)
                Text(desc)
                    .font(.system(size: metrics.rowDescSize - 1))
                    .foregroundColor(.white.opacity(0.50))
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ModifierBadge(forChord: key, size: metrics.badgeSize)
                    .padding(.top, 4)
                KeyCap(text: key, fontSize: metrics.keyCapSize)
                    .layoutPriority(1)
                Text(desc)
                    .font(.system(size: metrics.rowDescSize))
                    .foregroundColor(Color(red: 0.866, green: 0.894, blue: 0.933).opacity(0.68))
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
            .foregroundColor(Color(red: 0.866, green: 0.894, blue: 0.933))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .fixedSize(horizontal: true, vertical: false)
    }
}
