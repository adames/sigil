import Foundation
import WorkspaceState

/// Single seam between the picker and the window manager. Sync read at
/// overlay open; synchronous focus on commit (the overlay exits right
/// after, so blocking the main thread for one fast `aerospace focus` is
/// fine). Mirrors ws-prompt's `WorkspaceService` — one boundary that
/// keeps the picker decoupled from aerospace I/O.
protocol WindowSource {
    func loadWindows() -> [WindowItem]
    func focus(windowID: Int)
}

/// Production implementation: delegates to the configured WindowManager.
final class ProductionWindowSource: WindowSource {
    private let windowManager: WindowManager

    init(windowManager: WindowManager = WindowManagerFactory.create()) {
        self.windowManager = windowManager
    }

    func loadWindows() -> [WindowItem] {
        // `list-windows --all` includes minimized windows and windows on
        // hidden workspaces; aerospace exposes no visibility bit, so the
        // picker lists everything and lets focus pull the workspace in.
        guard let entries = try? windowManager.queryWindows() else { return [] }
        return entries.map { WindowItem(
            id: $0.id, app: $0.app, title: $0.title,
            workspace: $0.workspace, display: $0.display)
        }
    }

    func focus(windowID: Int) {
        do {
            try windowManager.focusWindow(id: windowID)
        } catch {
            FileHandle.standardError.write(Data(
                "ws-picker: focus window \(windowID) failed: \(error)\n".utf8))
        }
    }
}
