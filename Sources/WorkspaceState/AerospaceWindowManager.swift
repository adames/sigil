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

    public func focusSpace(index: Int) throws {
        throw WindowManagerError.notImplemented("aerospace: focusSpace")
    }

    public func sendWindowToSpace(index: Int, follow: Bool) throws {
        throw WindowManagerError.notImplemented("aerospace: sendWindowToSpace")
    }

    public func createSpace() throws -> Int {
        throw WindowManagerError.notImplemented("aerospace: createSpace")
    }

    public func destroySpace(index: Int) throws {
        throw WindowManagerError.notImplemented("aerospace: destroySpace")
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
