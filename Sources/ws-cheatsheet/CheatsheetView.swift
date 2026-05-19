import SwiftUI
import WsUI   // re-exports `Color(hex:)`

/// The HUD view, a *learning aid* shaped as a category mosaic:
///
/// - Each **column** is one family (system / terminal / vim / nvim+git).
///   Family color carries the categorical cue; physical adjacency
///   reinforces it.
/// - Within a column, cards stack tightly (no row alignment, no algorithm).
/// - Card layout is **declared** by `cheatsheet-layout.json` and produced
///   by `lib/cheatsheet-gen.py` from `@cs` annotations in the upstream
///   config files. The renderer just iterates the columns the JSON gave
///   it — no computation.
///
/// Within a card:
///   - section header → idea caption → row table.
///   - The vim-motion card opts into `customLayout: "keyboard"` and
///     renders a spatial keyboard above the table (Paivio dual-coding).
struct CheatsheetView: View {
    let document: CheatsheetDocument
    let timestamp: String

    // Compact layout: maximize density while preserving hierarchy
    private let outerHPadding: CGFloat = 20
    private let outerTopPadding: CGFloat = 20
    private let outerBottomPadding: CGFloat = 16
    private let columnSpacing: CGFloat = 12
    private let cardSpacing: CGFloat = 10

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                bannerStrip
                columnGrid
                footer
            }
            .padding(.horizontal, outerHPadding)
            .padding(.top, outerTopPadding)
            .padding(.bottom, outerBottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Static family columns fill available width, no scrolling.
    /// Each column gets equal width; cards compress vertically to fit.
    private var columnGrid: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            ForEach(document.columns) { column in
                VStack(spacing: cardSpacing) {
                    ForEach(column.sections) { section in
                        SectionCard(section: section)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
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

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Text("CAPS + ; (or Esc) TO CLOSE  ·  \(timestamp)")
                .font(.system(size: 9))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.25))
            Spacer()
        }
    }
}

// MARK: - SectionCard

private struct SectionCard: View {
    let section: CheatsheetDocument.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(section.title.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.7)
                    .foregroundColor(accentColor)
                    .padding(.bottom, 2)

                if let sub = section.sub, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.38))
                        .padding(.bottom, section.idea == nil ? 8 : 4)
                }

                if let idea = section.idea, !idea.isEmpty {
                    Text(idea)
                        .font(.system(size: 10))
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
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
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
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.22))
                    .frame(width: 60, alignment: .leading)
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.50))
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ModifierBadge(forChord: key)
                    .padding(.top, 4)
                KeyCap(text: key)
                    .layoutPriority(1)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.866, green: 0.894, blue: 0.933).opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private var accentColor: Color {
        FamilyColors.resolve(family: section.family, fallbackHex: section.color ?? "")
    }
}

// MARK: - KeyCap

/// Visual rendering of a key chord. Looks like a keycap with a faint border.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
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
