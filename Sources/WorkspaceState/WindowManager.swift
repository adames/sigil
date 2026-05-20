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

    /// Focus the workspace identified by `target`. Under aerospace this is
    /// `aerospace workspace <name>`; under yabai it resolves the target's
    /// workspaceName/displayUUID back to a yabai global slot via the
    /// `(displayUUID, workspaceName) → slot` lookup that
    /// `WorkspaceTarget` carries.
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
// Decodable structs the window manager returns from the read-side
// queries above. Modeled minimally — only fields current consumers
// read. Add a field when a consumer needs one; don't speculate.

/// One display, identified by its window-manager index plus its CG
/// frame. The frame is what `ws-autohide` needs to match the cursor's
/// screen to a yabai/aerospace display ordinal. Under v3, `displayUUID`
/// is the CG-stable identifier — present on aerospace returns, empty
/// string on yabai (filled in by AerospaceWindowManager).
public struct DisplayInfo: Decodable, Sendable {
    public let index: Int
    public let frame: Frame
    public let displayUUID: String

    public init(index: Int, frame: Frame, displayUUID: String = "") {
        self.index = index
        self.frame = frame
        self.displayUUID = displayUUID
    }

    enum CodingKeys: String, CodingKey {
        case index, frame, displayUUID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.index = try c.decode(Int.self, forKey: .index)
        self.frame = try c.decode(Frame.self, forKey: .frame)
        self.displayUUID = (try? c.decode(String.self, forKey: .displayUUID)) ?? ""
    }

    /// Display frame in CG points. yabai emits this as a nested object
    /// with `x`/`y`/`w`/`h` keys, so we mirror that shape.
    public struct Frame: Decodable, Sendable {
        public let x: Double
        public let y: Double
        public let w: Double
        public let h: Double
    }
}

/// One window, with the fields the picker uses to render rows and the
/// flags it filters by. yabai emits more fields (frame, role, opacity,
/// …) — they're ignored on decode.
public struct WindowInfo: Decodable, Sendable {
    public let id: Int
    public let app: String
    public let title: String
    public let space: Int
    public let display: Int
    public let isVisible: Bool
    public let isMinimized: Bool

    enum CodingKeys: String, CodingKey {
        case id, app, title, space, display
        case isVisible = "is-visible"
        case isMinimized = "is-minimized"
    }
}

/// One space / workspace. Post-fork-B, the source of truth for
/// "which workspace lives on which display" is the
/// `(displayUUID, workspaceName)` pair carried here, not the slot
/// `index`. `index` and `display` remain as derived/legacy convenience
/// fields for the statusbar pill renderer and any consumers that still
/// think in global slots; aerospace synthesizes them as a per-display
/// ordinal + monitor index.
///
/// Custom `Decodable` because yabai's `--query --spaces` JSON has
/// `index` and `display` but no `workspaceName`/`displayUUID` — those
/// are synthesized post-decode by the YabaiWindowManager. Aerospace's
/// implementation constructs `SpaceInfo` directly (not via decode) and
/// supplies real values for all four fields.
public struct SpaceInfo: Decodable, Sendable {
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

    enum CodingKeys: String, CodingKey {
        case index, display, displayUUID, workspaceName, label
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let index = try c.decode(Int.self, forKey: .index)
        let display = try c.decode(Int.self, forKey: .display)
        // Aerospace path may emit these directly. Yabai path leaves them
        // absent; we synthesize. `label` is yabai's space label and is
        // preferred as workspaceName when present.
        let uuid = try c.decodeIfPresent(String.self, forKey: .displayUUID)
        let nameField = try c.decodeIfPresent(String.self, forKey: .workspaceName)
        let label = try c.decodeIfPresent(String.self, forKey: .label)
        self.index = index
        self.display = display
        self.displayUUID = uuid ?? ""
        let resolvedName = nameField
            ?? (label?.isEmpty == false ? label : nil)
            ?? "slot\(index)"
        self.workspaceName = resolvedName
    }
}

/// Composite key identifying a workspace under fork B's per-display
/// data model: `(displayUUID, workspaceName)`. `displayUUID` is the
/// CoreGraphics-derived UUID from `CGDisplayCreateUUIDFromDisplayID` —
/// stable across reboots and hot-plug. `workspaceName` is the aerospace
/// workspace name (or the synthesized "slot<N>" name for yabai-era
/// slots that haven't been reconciled yet).
public struct WorkspaceTarget: Hashable, Sendable {
    public let displayUUID: String
    public let workspaceName: String

    public init(displayUUID: String, workspaceName: String) {
        self.displayUUID = displayUUID
        self.workspaceName = workspaceName
    }

    /// Convenience constructor for transitional callers that still hold
    /// a `SpaceInfo`. Equivalent to copying the two key fields.
    public init(_ space: SpaceInfo) {
        self.displayUUID = space.displayUUID
        self.workspaceName = space.workspaceName
    }
}
