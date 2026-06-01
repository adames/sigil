import Foundation

/// AeroSpace is the only real backend; `.none` covers tests and machines
/// where aerospace isn't installed.
public protocol WindowManager {
    static var kind: WindowManagerKind { get }
    var binaryPath: String { get }

    func focusSpace(target: WorkspaceTarget) throws
    func sendWindowToSpace(target: WorkspaceTarget, follow: Bool) throws
    func focusedSpace() throws -> WorkspaceTarget?
    func focusedSpaceIndex() throws -> Int?
    func focusWindow(id: Int) throws
    func queryDisplays() throws -> [DisplayInfo]
    func queryWindows() throws -> [WindowInfo]
    func querySpaces() throws -> [SpaceInfo]
}

public enum WindowManagerKind: String, Sendable {
    case aerospace
    case none
}

public enum WindowManagerError: Error {
    case binaryNotFound(String)
    case commandFailed(String)
    case parseError(String)
    case notImplemented(String)
    case unavailable
}

public struct DisplayInfo: Sendable {
    public let index: Int
    public let frame: Frame
    public let displayUUID: String

    public init(index: Int, frame: Frame, displayUUID: String = "") {
        self.index = index
        self.frame = frame
        self.displayUUID = displayUUID
    }

    /// Display frame in CG points — `x`/`y`/`w`/`h`.
    public struct Frame: Sendable {
        public let x: Double
        public let y: Double
        public let w: Double
        public let h: Double

        public init(x: Double, y: Double, w: Double, h: Double) {
            self.x = x; self.y = y; self.w = w; self.h = h
        }
    }
}

public struct WindowInfo: Sendable {
    public let id: Int
    public let app: String
    public let title: String
    public let space: Int
    public let display: Int
    public let isVisible: Bool
    public let isMinimized: Bool

    public init(
        id: Int,
        app: String,
        title: String,
        space: Int,
        display: Int,
        isVisible: Bool,
        isMinimized: Bool
    ) {
        self.id = id
        self.app = app
        self.title = title
        self.space = space
        self.display = display
        self.isVisible = isVisible
        self.isMinimized = isMinimized
    }
}

public struct SpaceInfo: Sendable {
    public let index: Int
    public let display: Int
    public let displayUUID: String
    public let workspaceName: String

    public init(
        index: Int,
        display: Int,
        displayUUID: String,
        workspaceName: String
    ) {
        self.index = index
        self.display = display
        self.displayUUID = displayUUID
        self.workspaceName = workspaceName
    }
}

/// Stable workspace identity: CG display UUID + aerospace workspace name.
public struct WorkspaceTarget: Hashable, Sendable {
    public let displayUUID: String
    public let workspaceName: String

    public init(displayUUID: String, workspaceName: String) {
        self.displayUUID = displayUUID
        self.workspaceName = workspaceName
    }

    public init(_ space: SpaceInfo) {
        self.displayUUID = space.displayUUID
        self.workspaceName = space.workspaceName
    }
}
