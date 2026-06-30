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

    /// Columns of the active lens, sized to the display.
    ///
    /// `CheatsheetLayout.plan` decides everything from the bounded
    /// `geo.size`: how many columns fit the width (clamped to the section
    /// count, so there is never a stranded empty column), how the sections
    /// balance into them, and which typographic tier keeps the tallest
    /// column inside the height. The HStack collapses to its natural width
    /// and centers — so a 2-section lens is a calm centered pair on a wide
    /// monitor and a denser, fitted mosaic on a small laptop. Nothing here
    /// reads SwiftUI's fitting size, so the window cannot grow off-screen.
    private var columnGrid: some View {
        GeometryReader { geo in
            let ordered = document.orderedSections(view: currentLens)
            let plan = CheatsheetLayout.plan(
                for: ordered,
                availableWidth: geo.size.width,
                availableHeight: geo.size.height
            )

            HStack(alignment: .top, spacing: plan.metrics.columnSpacing) {
                ForEach(Array(plan.columns.enumerated()), id: \.offset) { _, column in
                    columnStack(column, plan: plan)
                }
            }
            // Center the mosaic when it fits: on a tall external monitor the
            // cards sit centered rather than stranded at the top edge; on a
            // tight laptop the fitted content already ~fills, so centering is
            // a no-op. When even the densest tier overflows (a tiny zoomed
            // display), top-align so the first rows stay visible.
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: plan.fits ? .center : .top
            )
        }
    }

    /// One display column: its sections stacked top-down at the plan's
    /// width and tier.
    private func columnStack(
        _ sections: [CheatsheetDocument.Section],
        plan: LayoutPlan
    ) -> some View {
        VStack(spacing: plan.metrics.cardSpacing) {
            ForEach(sections) { section in
                SectionCard(section: section, metrics: plan.metrics)
            }
        }
        .frame(width: plan.columnWidth, alignment: .top)
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
