import AppKit
import SwiftUI
import WsUI

/// SwiftUI overlay for the **change application** prompt (binary: ws-picker).
/// Lists every visible window across every space; selecting one focuses
/// that window, which aerospace follows by jumping to its space. Visual
/// contract matches ws-prompt's PromptView so the workspace-prompt suite
/// feels like one tool: same card geometry, Catppuccin palette, pill style.
struct PickerView: View {
    @ObservedObject var controller: PickerController
    /// Card width, computed once from the host screen by WsPickerApp. The
    /// window is sized to this (+ margins), so the card never resizes it.
    let cardWidth: CGFloat

    private var matches: [WindowItem] { controller.currentMatches() }

    var body: some View {
        // The host window is already sized + positioned (top-centred) by
        // WsPickerApp; pin the card to the top and let matches fill in as
        // they load (kept identical to ws-prompt PromptView for parity).
        card(width: cardWidth)
            .padding(PromptStyle.cardMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func card(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            queryField
            listRows
            hint
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: width)
        .background(
            // Solid card — no behind-window blur (matches PromptView).
            RoundedRectangle(cornerRadius: PromptStyle.cardCorner)
                .fill(Palette.resolved.mantle)
                .overlay(
                    RoundedRectangle(cornerRadius: PromptStyle.cardCorner)
                        .strokeBorder(Palette.resolved.surface0.opacity(0.85), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("find window")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.resolved.text)
            Spacer()
            modeChip
        }
    }

    private var modeChip: some View {
        Text("FOCUS")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Palette.resolved.base)
            .padding(.horizontal, 10)
            .frame(height: PromptStyle.pillHeight)
            .background(
                RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                    .fill(Palette.resolved.blue)
            )
    }

    // MARK: - Query field

    private var queryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Palette.resolved.blue)
                .frame(width: 14)
            Text(displayQuery)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(controller.query.isEmpty ? Palette.resolved.overlay0 : Palette.resolved.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("↵")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Palette.resolved.overlay0)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                .fill(Palette.resolved.base.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                        .strokeBorder(Palette.resolved.surface0.opacity(0.8), lineWidth: 1)
                )
        )
    }

    private var displayQuery: String {
        // Placeholder describes the input; the footer owns the key legend
        // (no more duplicated ↵ explanation across the two).
        controller.query.isEmpty ? "type an app or window title…" : controller.query
    }

    // MARK: - List

    private var listRows: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { (idx, item) in
                    windowRow(item: item, selected: idx == controller.selection)
                }
                if matches.isEmpty && !controller.isLoading {
                    Text(controller.query.isEmpty
                         ? "no open windows"
                         : "no windows match “\(controller.query)” · backspace to widen")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.resolved.hint)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 18)
                }
            }
        }
        .frame(maxHeight: PromptStyle.listMaxHeight)
    }

    /// One row mirrors a workspace pill from PromptView: app icon + name
    /// on the left, window title on the right, workspace name at the
    /// far end. Selected row fills with Palette.resolved.blue (the same color
    /// the focus prompt uses for its navigate-action chip).
    private func windowRow(item: WindowItem, selected: Bool) -> some View {
        let accent = Palette.resolved.blue
        let textColor: Color = selected ? Palette.resolved.base : Palette.resolved.text
        let subColor:  Color = selected ? Palette.resolved.base.opacity(0.75) : Palette.resolved.overlay1
        return HStack(spacing: 10) {
            iconView(for: item.app, tinted: selected)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayLabel)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !item.title.isEmpty {
                    Text(item.app)
                        .font(.system(size: 10))
                        .foregroundColor(subColor)
                        .lineLimit(1)
                }
            }
            Spacer()
            if !item.workspace.isEmpty {
                Text(item.workspace)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(selected ? Palette.resolved.base : accent)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: PromptStyle.pillHeight + 12)
        .background(
            RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                .fill(selected ? accent : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                        .strokeBorder(accent.opacity(selected ? 1 : 0.55), lineWidth: 1.5)
                )
        )
    }

    /// App icon rendered at row height. NSWorkspace's icon cache means
    /// repeated lookups are cheap — fine to resolve inline per row.
    @ViewBuilder
    private func iconView(for app: String, tinted selected: Bool) -> some View {
        if let nsImage = AppIconResolver.icon(forAppName: app) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .opacity(selected ? 0.95 : 1.0)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(selected ? Palette.resolved.base : Palette.resolved.overlay1)
        }
    }

    private var hint: some View {
        Text("↵ focus window · tab/⇧tab select · esc cancels")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Palette.resolved.hint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Resolve an app's icon by its display name. Caches results — misses
/// included, so an unresolvable app doesn't rescan the running-app list
/// on every keystroke × row.
enum AppIconResolver {
    private static var cache: [String: NSImage?] = [:]

    static func icon(forAppName name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        let resolved = resolve(name)
        cache[name] = resolved
        return resolved
    }

    private static func resolve(_ name: String) -> NSImage? {
        // `name` is usually a display name, but aerospace falls back to
        // the bundle id when an app has no name — try the cheap bundle-id
        // lookup first.
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: name) {
            return workspace.icon(forFile: url.path)
        }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: name)
            .first(where: { $0.icon != nil }) {
            return app.icon
        }
        // Last resort — scan running apps by display name. Slower than
        // a bundle-ID lookup but only runs on a cache miss.
        return workspace.runningApplications
            .first(where: { $0.localizedName == name })?
            .icon
    }
}
