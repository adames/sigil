import Foundation

public enum WindowManagerFactory {
    /// AeroSpace when its binary is present, otherwise a no-op manager so
    /// callers degrade gracefully on machines without it. Probes the same
    /// resolved path it hands to the manager — `WindowManagerConfig`
    /// honors the `AEROSPACE_BIN` override, so probing the Homebrew
    /// locations directly would defeat it.
    public static func create() -> WindowManager {
        let path = WindowManagerConfig.binaryPath
        return FileManager.default.isExecutableFile(atPath: path)
            ? AerospaceWindowManager(binaryPath: path)
            : NoOpWindowManager()
    }
}

public final class NoOpWindowManager: WindowManager {
    public init() {}

    public func focusWindow(id: Int) throws {
        throw WindowManagerError.unavailable
    }

    public func queryWindows() throws -> [WindowInfo] { [] }
    public func querySpaces() throws -> [SpaceInfo] { [] }
}
