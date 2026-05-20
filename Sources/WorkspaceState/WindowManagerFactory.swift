import Foundation

/// Factory for creating the appropriate WindowManager based on configuration.
///
/// Post-Phase-6 there's only one real backend: AeroSpace. `NoOpWindowManager`
/// is retained for tests and for setups where no daemon is available. The
/// `WindowManagerKind` enum survives as a type seam in case a third
/// implementation is ever introduced — but there's no branching here today.
public enum WindowManagerFactory {
    /// Create a WindowManager based on the current configuration.
    /// Defaults to aerospace.
    public static func create() -> WindowManager {
        switch configuredKind() {
        case .aerospace:
            return AerospaceWindowManager(binaryPath: WindowManagerConfig.binaryPath)
        case .none, .yabai, .rectangle:
            // `.yabai` and `.rectangle` survive in the enum only to keep
            // any existing WORKSPACE_WINDOW_MANAGER=yabai env vars from
            // crashing the factory mid-transition — they degrade to no-op.
            return NoOpWindowManager()
        }
    }

    /// Get the configured window manager kind. WORKSPACE_WINDOW_MANAGER
    /// wins when set; otherwise falls back to aerospace presence on disk.
    public static func configuredKind() -> WindowManagerKind {
        if let env = ProcessInfo.processInfo.environment["WORKSPACE_WINDOW_MANAGER"],
           let kind = WindowManagerKind(rawValue: env) {
            return kind
        }
        let aerospacePaths = [
            "/opt/homebrew/bin/aerospace",
            "/usr/local/bin/aerospace",
        ]
        for path in aerospacePaths where FileManager.default.fileExists(atPath: path) {
            return .aerospace
        }
        return .none
    }

    /// Check if a window manager is available on disk.
    public static func isAvailable(_ kind: WindowManagerKind) -> Bool {
        switch kind {
        case .aerospace:
            let paths = ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
            return paths.contains { FileManager.default.fileExists(atPath: $0) }
        case .rectangle:
            return FileManager.default.fileExists(atPath: "/Applications/Rectangle.app")
        case .yabai:
            // Always false post-burn — yabai support is retired.
            return false
        case .none:
            return true
        }
    }
}

/// No-op window manager for when no window manager is available.
public final class NoOpWindowManager: WindowManager {
    public static let kind: WindowManagerKind = .none
    public let binaryPath: String = ""

    public init() {}

    public func focusSpace(target: WorkspaceTarget) throws {
        throw WindowManagerError.unavailable
    }

    public func sendWindowToSpace(target: WorkspaceTarget, follow: Bool) throws {
        throw WindowManagerError.unavailable
    }

    public func createSpace() throws -> WorkspaceTarget {
        throw WindowManagerError.unavailable
    }

    public func destroySpace(target: WorkspaceTarget) throws {
        throw WindowManagerError.unavailable
    }

    public func focusedSpace() throws -> WorkspaceTarget? {
        return nil
    }

    public func focusedSpaceIndex() throws -> Int? {
        return nil
    }

    public func spaceCount() throws -> Int {
        return 0
    }

    public func focusedWindowID() throws -> Int? {
        return nil
    }

    public func focusWindow(id: Int) throws {
        throw WindowManagerError.unavailable
    }

    public func queryDisplays() throws -> [DisplayInfo] { [] }
    public func queryWindows() throws -> [WindowInfo] { [] }
    public func querySpaces() throws -> [SpaceInfo] { [] }
}
