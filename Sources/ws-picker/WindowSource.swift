import Foundation
import WorkspaceState

/// Single seam between the picker and the window manager. Sync read at
/// overlay open; async fire-and-forget focus on commit. Mirrors
/// ws-prompt's `WorkspaceService` protocol — one boundary, one place
/// to mock.
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
        guard let entries = try? windowManager.queryWindows() else { return [] }
        // Drop windows the user can't visually see: minimized, on a
        // hidden space, etc. The picker is "switch to a visible window"
        // — exposing zombies just dilutes the fuzzy match.
        return entries
            .filter { $0.isVisible && !$0.isMinimized }
            .map { WindowItem(
                id: $0.id, app: $0.app, title: $0.title,
                space: $0.space, display: $0.display)
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
