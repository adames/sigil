import Foundation

/// Abstraction over the window manager. AeroSpace is the only real
/// backend post-migration; `WindowManagerKind` keeps `.none` as the
/// degenerate case for tests and for explicit-disable setups, and stays
/// declared as an enum so a third implementation could slot in without
/// touching call sites.
public protocol WindowManager {
    /// The type of window manager (aerospace, none)
    static var kind: WindowManagerKind { get }

    /// Path to the window manager binary
    var binaryPath: String { get }

    // MARK: - Space Operations

    /// Focus the workspace identified by `target` — shells to
    /// `aerospace workspace <workspaceName>`.
    func focusSpace(target: WorkspaceTarget) throws

    /// Send the focused window to the workspace identified by `target`,
    /// optionally following it.
    func sendWindowToSpace(target: WorkspaceTarget, follow: Bool) throws

    /// Create a new workspace. Throws `.notImplemented` under aerospace
    /// (workspaces are declared statically in aerospace.toml). Yabai
    /// synthesizes a `WorkspaceTarget` for the newly-created slot.
    func createSpace() throws -> WorkspaceTarget

    /// Destroy the workspace identified by `target`. Throws
    /// `.notImplemented` under aerospace (same reason as `createSpace()`).
    func destroySpace(target: WorkspaceTarget) throws

    /// Get the currently focused workspace, or nil if no window manager.
    func focusedSpace() throws -> WorkspaceTarget?

    /// Get the currently focused space's legacy global slot index (1-based).
    /// Retained as a transitional convenience for consumers (statusbar
    /// cache fallback, ws-prompt index renderers) that still think in
    /// slots. Aerospace synthesizes the per-display ordinal here. Will be
    /// retired in a follow-up once all consumers move to `focusedSpace()`.
    func focusedSpaceIndex() throws -> Int?

    /// Get the total number of spaces / workspaces.
    func spaceCount() throws -> Int

    // MARK: - Window Operations

    /// Get the ID of the currently focused window
    func focusedWindowID() throws -> Int?

    /// Focus the window with the given ID
    func focusWindow(id: Int) throws

    // MARK: - Read-side queries

    /// Snapshot of every display the window manager knows about.
    /// Consumers use this for the `display index ↔ frame` mapping
    /// (autohide's per-display trigger band).
    func queryDisplays() throws -> [DisplayInfo]

    /// Snapshot of every window visible to the window manager. Order is
    /// the window manager's order; consumers filter / re-sort.
    func queryWindows() throws -> [WindowInfo]

    /// Snapshot of every space (index + owning display). The
    /// (index, display) tuple is the source of truth for "which space
    /// lives on which display" used by the manage overlay's optimistic
    /// pre-paint and statusbar transitions.
    func querySpaces() throws -> [SpaceInfo]
}

public enum WindowManagerKind: String, Sendable {
    case aerospace
    case none
}

/// Errors that can occur during window manager operations
public enum WindowManagerError: Error {
    case binaryNotFound(String)
    case commandFailed(String)
    case parseError(String)
    case notImplemented(String)
    case unavailable
}

// MARK: - Wire shapes
//
// Plain value types the window manager returns from the read-side
// queries above. Modeled minimally — only fields current consumers
// read. AerospaceWindowManager constructs them directly via memberwise
// inits after parsing aerospace's JSON; nothing decodes these structs
// from JSON, so they're not Codable. Add a field when a consumer needs
// one; don't speculate.

/// One display, identified by its window-manager index plus its CG
/// frame. The frame is what `ws-autohide` needs to match the cursor's
/// screen to an aerospace display ordinal. `displayUUID` is the
/// CG-stable identifier (`CGDisplayCreateUUIDFromDisplayID`) —
/// AerospaceWindowManager fills it in from the bridged CG lookup.
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

/// One window, with the fields the picker uses to render rows and the
/// flags it filters by.
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

/// One workspace. Identity is the `(displayUUID, workspaceName)` tuple;
/// `index` is a per-display ordinal (1-based) and `display` is the
/// aerospace monitor ordinal that workspace lives on. Both ordinals
/// are synthesized at query time and shouldn't be held across
/// reorderings.
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

/// Composite key identifying a workspace: `(displayUUID, workspaceName)`.
/// `displayUUID` is the CoreGraphics UUID from
/// `CGDisplayCreateUUIDFromDisplayID` — stable across reboots and
/// hot-plug. `workspaceName` is the aerospace workspace identifier.
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
