import SwiftUI
import WsUI

// Visual vocabulary (palette, typography, pill geometry) lives in
// WsUI/DesignSystem.swift — see `Catppuccin` and `PromptStyle`.

/// Number-only workspace switcher for the send (follow) prompt. Lists the
/// live workspaces so you can see which digit maps to which; a digit
/// commits (see PromptController) and esc cancels. No query field, no
/// selection — modeled on AeroSpace's numeric workspace switch.
struct PromptView: View {
    @ObservedObject var controller: PromptController
    /// Card width, computed once from the host screen by WsPromptApp. The
    /// window is sized to this (+ margins), so the card never resizes it.
    let cardWidth: CGFloat
    /// Read once at launch from `NSWorkspace.shared
    /// .accessibilityDisplayShouldReduceMotion` (see WsPromptApp). When
    /// true, the shake offset is skipped entirely (the card never moves)
    /// and OverlayCard's border pulse carries the reject feedback alone.
    var reduceMotion: Bool = false

    private var workspaces: [Workspace] { controller.workspaces }

    var body: some View {
        // The host window is already sized + positioned (top-centred) by
        // WsPromptApp, so the view just pins the card to the top and lets
        // the rows fill in once they load — no GeometryReader, no centring
        // spacers, nothing that would make AppKit resize the window.
        OverlayCard(
            title: "send window",
            width: cardWidth,
            nudge: controller.nudge,
            reduceMotion: reduceMotion,
            // Green = move-and-follow.
            chip: ModeChip("SEND", accent: Palette.resolved.green)
        ) {
            listRows
            hint
        }
        .padding(PromptStyle.cardMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Workspace list

    private var listRows: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(workspaces.enumerated()), id: \.offset) { (idx, ws) in
                    workspaceRow(ws: ws, selected: idx == controller.selection)
                }
                if workspaces.isEmpty && !controller.isLoading {
                    Text("no workspaces")
                        .font(.system(size: PromptStyle.hintSize))
                        .foregroundColor(Palette.resolved.hint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
            }
        }
        .frame(maxHeight: PromptStyle.listMaxHeight)
    }

    /// One workspace row, styled as a chip: the slot digit, optional icon,
    /// and name. `0` labels slot 10 to match the commit digit. The selected
    /// row fills with its slot color (mirrors the picker's selection so the
    /// two overlays share one interaction model).
    private func workspaceRow(ws: Workspace, selected: Bool) -> some View {
        let slot = Color(hex: ws.color) ?? Palette.resolved.overlay1
        let digitColor: Color = selected ? Palette.resolved.base : slot
        let nameColor: Color = selected ? Palette.resolved.base : Palette.resolved.text
        return HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(digitLabel(ws.index))
                    .font(.system(size: PromptStyle.bodySize, weight: .medium))
                    .foregroundColor(digitColor)
                iconView(ws: ws, tint: digitColor)
            }
            .frame(width: 56, alignment: .leading)

            Text(ws.name)
                .font(.system(size: PromptStyle.bodySize))
                .foregroundColor(nameColor)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: PromptStyle.pillHeight + 6)
        .background(
            RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                .fill(selected ? slot : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                        .strokeBorder(slot.opacity(selected ? 1 : 0.55), lineWidth: 1.5)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("workspace \(ws.name), slot \(digitLabel(ws.index))")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Slot 10 commits on `0`, so show `0` for index 10; everything else
    /// shows its own number. Slots past 10 have no digit chord.
    private func digitLabel(_ index: Int) -> String {
        index == 10 ? "0" : String(index)
    }

    /// `icon` is either an SF Symbol name or a Nerd Font glyph —
    /// `iconKind` says which. A Nerd Font glyph through
    /// `Image(systemName:)` resolves to nothing, so it renders as text
    /// in the font that owns the codepoint.
    @ViewBuilder
    private func iconView(ws: Workspace, tint: Color) -> some View {
        if let icon = ws.icon, !icon.isEmpty {
            switch ws.iconKind {
            case .sfSymbol:
                Image(systemName: icon)
                    .font(.system(size: PromptStyle.hintSize, weight: .semibold))
                    .foregroundColor(tint)
            case .nerdFont:
                Text(icon)
                    .font(.custom(ws.iconFontFamily ?? "", size: PromptStyle.bodySize))
                    .foregroundColor(tint)
            case .none:
                EmptyView()
            }
        }
    }

    // MARK: - Hint

    private var hint: some View {
        Text("↵ or 1–0 sends + follows · ↑↓ select · esc cancels")
            .font(.system(size: PromptStyle.hintSize, weight: .medium))
            .foregroundColor(Palette.resolved.hint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
