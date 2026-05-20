import Foundation

/// Factory for the WindowManager backend. AeroSpace is the only real
/// implementation; `NoOpWindowManager` covers tests + setups where the
/// daemon isn't installed.
public enum WindowManagerFactory {
    /// Aerospace when its binary is on disk; no-op otherwise.
    public static func create() -> WindowManager {
        switch configuredKind() {
        case .aerospace:
            return AerospaceWindowManager(binaryPath: WindowManagerConfig.binaryPath)
        case .none:
            return NoOpWindowManager()
        }
    }

    /// Pick the active backend. Aerospace when the binary exists on
    /// disk; no-op otherwise.
    public static func configuredKind() -> WindowManagerKind {
        let aerospacePaths = [
            "/opt/homebrew/bin/aerospace",
            "/usr/local/bin/aerospace",
        ]
        for path in aerospacePaths where FileManager.default.fileExists(atPath: path) {
            return .aerospace
        }
        return .none
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

    public func focusedSpace() throws -> WorkspaceTarget? {
        return nil
    }

    public func focusedSpaceIndex() throws -> Int? {
        return nil
    }

    public func focusWindow(id: Int) throws {
        throw WindowManagerError.unavailable
    }

    public func queryDisplays() throws -> [DisplayInfo] { [] }
    public func queryWindows() throws -> [WindowInfo] { [] }
    public func querySpaces() throws -> [SpaceInfo] { [] }
}
