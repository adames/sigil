import Foundation

/// WindowManager implementation for aerospace
/// (https://github.com/nikitabobko/AeroSpace).
///
/// Phase 1 scaffold: every method throws `.notImplemented`. The class
/// exists so the factory has a real type to dispatch to and the
/// protocol is exercised on two implementations. Phase 2 fills in
/// the real CLI invocations and the hybrid `(display, workspace)`
/// lookup that maps Sigil slot indices to aerospace workspaces.
public final class AerospaceWindowManager: WindowManager {
    public static let kind: WindowManagerKind = .aerospace

    public let binaryPath: String

    public init(binaryPath: String? = nil) {
        self.binaryPath = binaryPath ?? "/opt/homebrew/bin/aerospace"
    }

    // MARK: - Space Operations

    public func focusSpace(target: WorkspaceTarget) throws {
        throw WindowManagerError.notImplemented("aerospace: focusSpace")
    }

    public func sendWindowToSpace(target: WorkspaceTarget, follow: Bool) throws {
        throw WindowManagerError.notImplemented("aerospace: sendWindowToSpace")
    }

    public func createSpace() throws -> WorkspaceTarget {
        // AeroSpace can't create workspaces at runtime — they're declared
        // statically in aerospace.toml. This stays as a hard error after
        // Phase 2 fills in the rest; ws-prompt is rewired in Phase 5 to
        // not call this under aerospace.
        throw WindowManagerError.notImplemented("aerospace: createSpace")
    }

    public func destroySpace(target: WorkspaceTarget) throws {
        // Same as createSpace — aerospace.toml owns workspace existence.
        throw WindowManagerError.notImplemented("aerospace: destroySpace")
    }

    public func focusedSpace() throws -> WorkspaceTarget? {
        throw WindowManagerError.notImplemented("aerospace: focusedSpace")
    }

    public func focusedSpaceIndex() throws -> Int? {
        throw WindowManagerError.notImplemented("aerospace: focusedSpaceIndex")
    }

    public func spaceCount() throws -> Int {
        throw WindowManagerError.notImplemented("aerospace: spaceCount")
    }

    // MARK: - Window Operations

    public func focusedWindowID() throws -> Int? {
        throw WindowManagerError.notImplemented("aerospace: focusedWindowID")
    }

    public func focusWindow(id: Int) throws {
        throw WindowManagerError.notImplemented("aerospace: focusWindow")
    }

    // MARK: - Read-side queries

    public func queryDisplays() throws -> [DisplayInfo] {
        throw WindowManagerError.notImplemented("aerospace: queryDisplays")
    }

    public func queryWindows() throws -> [WindowInfo] {
        throw WindowManagerError.notImplemented("aerospace: queryWindows")
    }

    public func querySpaces() throws -> [SpaceInfo] {
        throw WindowManagerError.notImplemented("aerospace: querySpaces")
    }
}
