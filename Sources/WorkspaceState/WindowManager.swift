import Foundation

/// AeroSpace is the only real backend; `NoOpWindowManager` covers machines
/// where aerospace isn't installed.
///
/// Deliberately read-mostly: focus/send mutations go through the bash
/// helpers (`ws-focus`, `ws-send-follow`), which own validation and user
/// notification. The Swift side only needs window focus (ws-picker's
/// commit) plus the two read queries the overlays render from.
public protocol WindowManager {
    func focusWindow(id: Int) throws
    func queryWindows() throws -> [WindowInfo]
    func querySpaces() throws -> [SpaceInfo]
}

public enum WindowManagerError: Error {
    case commandFailed(String)
    case parseError(String)
    case unavailable
}

public struct WindowInfo: Sendable {
    public let id: Int
    public let app: String
    public let title: String
    /// AeroSpace workspace name (workspaces are string-named; there is
    /// no numeric space ordinal at this layer).
    public let workspace: String
    public let display: Int

    public init(
        id: Int,
        app: String,
        title: String,
        workspace: String,
        display: Int
    ) {
        self.id = id
        self.app = app
        self.title = title
        self.workspace = workspace
        self.display = display
    }
}

public struct SpaceInfo: Sendable {
    public let display: Int
    public let displayUUID: String
    public let workspaceName: String

    public init(
        display: Int,
        displayUUID: String,
        workspaceName: String
    ) {
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
}
