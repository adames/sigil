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

    private var workspaces: [Workspace] { controller.workspaces }

    var body: some View {
        // Fill the full hosting view so the VStack's default `.center`
        // alignment centers the card horizontally on screen.
        ZStack {
            // No background scrim. The borderless window is transparent
            // (isOpaque=false in WsPromptApp); the card's own opaque
            // catppuccin background carries the visual weight so the
            // prompt floats above the live desktop instead of dimming it.
            VStack(spacing: 14) {
                Spacer().frame(height: PromptStyle.topInset)
                card
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            listRows
            hint
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: PromptStyle.cardCorner)
                .fill(Catppuccin.mantle.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: PromptStyle.cardCorner)
                        .strokeBorder(Catppuccin.surface0.opacity(0.85), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 6)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("send window")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Catppuccin.text)
            Spacer()
            modeChip
        }
    }

    /// Mode chip — fixed corner, 22pt tall, full-color fill, dark
    /// catppuccin text. Green = move-and-follow.
    private var modeChip: some View {
        Text("SEND")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Catppuccin.base)
            .padding(.horizontal, 10)
            .frame(height: PromptStyle.pillHeight)
            .background(
                RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                    .fill(Catppuccin.green)
            )
    }

    // MARK: - Workspace list

    private var listRows: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(workspaces.enumerated()), id: \.offset) { (_, ws) in
                    workspaceRow(ws: ws)
                }
                if workspaces.isEmpty {
                    Text("no workspaces")
                        .font(.system(size: 11))
                        .foregroundColor(Catppuccin.overlay0)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
            }
        }
        .frame(maxHeight: 360)
    }

    /// One workspace row, styled as a chip: the slot digit, optional icon,
    /// and name. `0` labels slot 10 to match the commit digit.
    private func workspaceRow(ws: Workspace) -> some View {
        let slot = Color(hex: ws.color) ?? Catppuccin.overlay1
        return HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(digitLabel(ws.index))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(slot)
                iconView(ws: ws, tint: slot)
            }
            .frame(width: 56, alignment: .leading)

            Text(ws.name)
                .font(.system(size: 12))
                .foregroundColor(Catppuccin.text)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: PromptStyle.pillHeight + 6)
        .background(
            RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                .fill(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                        .strokeBorder(slot.opacity(0.55), lineWidth: 1.5)
                )
        )
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tint)
            case .nerdFont:
                Text(icon)
                    .font(.custom(ws.iconFontFamily ?? "", size: 12))
                    .foregroundColor(tint)
            case .none:
                EmptyView()
            }
        }
    }

    // MARK: - Hint

    private var hint: some View {
        Text("1–0 sends + follows · esc cancels")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Catppuccin.overlay0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
