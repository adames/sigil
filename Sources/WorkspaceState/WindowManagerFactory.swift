import Foundation

public enum WindowManagerFactory {
    /// AeroSpace when its binary is installed, otherwise a no-op manager so
    /// callers degrade gracefully on machines without it.
    public static func create() -> WindowManager {
        let aerospacePaths = [
            "/opt/homebrew/bin/aerospace",
            "/usr/local/bin/aerospace",
        ]
        let aerospaceInstalled = aerospacePaths.contains {
            FileManager.default.fileExists(atPath: $0)
        }
        return aerospaceInstalled
            ? AerospaceWindowManager(binaryPath: WindowManagerConfig.binaryPath)
            : NoOpWindowManager()
    }
}

public final class NoOpWindowManager: WindowManager {
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
