import Foundation

/// Abstraction over window managers (yabai, aerospace, rectangle, etc.)
/// Provides workspace/space operations without vendor-specific assumptions.
public protocol WindowManager {
    /// The type of window manager (yabai, aerospace, rectangle, none)
    static var kind: WindowManagerKind { get }

    /// Path to the window manager binary
    var binaryPath: String { get }

    // MARK: - Space Operations

    /// Focus the space with the given index (1-based)
    func focusSpace(index: Int) throws

    /// Send the focused window to the space with the given index, optionally following it
    func sendWindowToSpace(index: Int, follow: Bool) throws

    /// Create a new space, returning its index
    func createSpace() throws -> Int

    /// Destroy the space with the given index
    func destroySpace(index: Int) throws

    /// Get the currently focused space index (1-based)
    func focusedSpaceIndex() throws -> Int?

    /// Get the total number of spaces
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
    case yabai
    case aerospace
    case rectangle
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
/// screen to a yabai display index.
public struct DisplayInfo: Decodable, Sendable {
    public let index: Int
    public let frame: Frame

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

/// One space, with the slot index and the index of the display that
/// hosts it. The manage overlay uses the `(index, display)` pairing
/// for optimistic pre-paint; statusbar uses it for the per-display
/// pill strip.
public struct SpaceInfo: Decodable, Sendable {
    public let index: Int
    public let display: Int
}
