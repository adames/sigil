import Foundation

public enum WindowManagerFactory {
    public static func create() -> WindowManager {
        switch configuredKind() {
        case .aerospace:
            return AerospaceWindowManager(binaryPath: WindowManagerConfig.binaryPath)
        case .none:
            return NoOpWindowManager()
        }
    }

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
