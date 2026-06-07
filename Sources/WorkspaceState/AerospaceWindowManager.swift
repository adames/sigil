import AppKit
import Foundation
import CoreGraphics

/// WindowManager implementation for AeroSpace
/// (https://github.com/nikitabobko/AeroSpace).
///
/// Shells to the `aerospace` CLI for every operation. The CLI streams
/// JSON output via `--json`; we decode through small `Aerospace*` value
/// types and project onto the protocol's wire shapes.
///
/// Display identity bridging:
///   AeroSpace numbers monitors 1..N by an internal ordering that can
///   change on hot-plug. Sigil keys spaces.json on the CG-stable
///   `CGDisplayCreateUUIDFromDisplayID(…)` UUID. The bridge:
///     1. aerospace list-monitors --json → AerospaceMonitor[]
///     2. CG enumerate active displays via CGGetActiveDisplayList
///     3. match by frame intersection (AeroSpace's monitor frame ⇔
///        CGDisplayBounds), derive stable UUID per match
///
/// Workspaces are declared statically in aerospace.toml; runtime
/// create/destroy isn't supported. ws-prompt surfaces an edit-then-
/// reload help message for those flows.
public final class AerospaceWindowManager: WindowManager {
    public let binaryPath: String

    public init(binaryPath: String? = nil) {
        self.binaryPath = binaryPath ?? "/opt/homebrew/bin/aerospace"
    }

    // MARK: - Space Operations

    public func focusSpace(target: WorkspaceTarget) throws {
        try runAerospace(args: ["workspace", target.workspaceName])
    }

    public func sendWindowToSpace(target: WorkspaceTarget, follow: Bool) throws {
        var args = ["move-node-to-workspace"]
        if follow { args.append("--focus-follows-window") }
        args.append(target.workspaceName)
        try runAerospace(args: args)
    }

    public func focusedSpace() throws -> WorkspaceTarget? {
        guard let output = try runAerospaceWithOutput(args: [
            "list-workspaces", "--focused", "--json"
        ]) else { return nil }
        let parsed = try Self.decodeOrThrow(
            [AerospaceWorkspace].self,
            from: output,
            label: "list-workspaces --focused"
        )
        guard let first = parsed.first else { return nil }

        // Resolve displayUUID by joining against list-monitors.
        let monitors = (try? queryMonitorsRaw()) ?? []
        let displayUUID = Self.uuidForMonitor(
            id: first.monitorId,
            monitors: monitors,
            cgDisplays: Self.cgDisplaysByID()
        )
        return WorkspaceTarget(
            displayUUID: displayUUID,
            workspaceName: first.workspace
        )
    }

    public func focusedSpaceIndex() throws -> Int? {
        // Synthesize a per-display ordinal: focused workspace's position
        // in its monitor's ordered workspace list. Statusbar fallback
        // still uses this for its cache; the new focusedSpace() above is
        // the long-term path.
        guard let focused = try focusedSpace() else { return nil }
        let allSpaces = try querySpaces()
        let onSameMonitor = allSpaces
            .filter { $0.displayUUID == focused.displayUUID }
        return onSameMonitor.firstIndex(where: {
            $0.workspaceName == focused.workspaceName
        }).map { $0 + 1 }
    }

    // MARK: - Window Operations

    public func focusWindow(id: Int) throws {
        try runAerospace(args: ["focus", "--window-id", "\(id)"])
    }

    // MARK: - Read-side queries

    public func queryDisplays() throws -> [DisplayInfo] {
        let monitors = try queryMonitorsRawWithRetry()
        let cgIndex = Self.cgDisplaysByID()
        return monitors.map { mon in
            let (frame, uuid) = Self.cgMatch(
                monitorName: mon.monitorName,
                monitorId: mon.monitorId,
                cgDisplays: cgIndex
            )
            return DisplayInfo(
                index: mon.monitorId,
                frame: frame,
                displayUUID: uuid
            )
        }
    }

    public func queryWindows() throws -> [WindowInfo] {
        guard let output = try runAerospaceWithOutput(args: [
            "list-windows", "--all", "--json"
        ]) else { return [] }
        let parsed = try Self.decodeOrThrow(
            [AerospaceWindow].self,
            from: output,
            label: "list-windows --all"
        )
        // Join windows to their workspace's monitor to populate `display`.
        // AeroSpace's --all output already contains workspace + monitor
        // when present; fall back to 1 when missing.
        return parsed.map { w in
            WindowInfo(
                id: w.windowId,
                app: w.appName ?? w.appBundleId ?? "Unknown",
                title: w.windowTitle ?? "",
                space: 0,
                display: w.monitorId ?? 1,
                isVisible: true,
                isMinimized: false
            )
        }
    }

    public func querySpaces() throws -> [SpaceInfo] {
        guard let output = try runAerospaceWithOutput(args: [
            "list-workspaces", "--all", "--json"
        ]) else { return [] }
        let parsed = try Self.decodeOrThrow(
            [AerospaceWorkspace].self,
            from: output,
            label: "list-workspaces --all"
        )

        let monitors = (try? queryMonitorsRaw()) ?? []
        let cgIndex = Self.cgDisplaysByID()

        // Per-display ordinal: walk in order, increment per monitor.
        var ordinalByMonitor: [Int: Int] = [:]
        return parsed.map { w in
            let next = (ordinalByMonitor[w.monitorId] ?? 0) + 1
            ordinalByMonitor[w.monitorId] = next
            let uuid = Self.uuidForMonitor(
                id: w.monitorId,
                monitors: monitors,
                cgDisplays: cgIndex
            )
            return SpaceInfo(
                index: next,
                display: w.monitorId,
                displayUUID: uuid,
                workspaceName: w.workspace
            )
        }
    }

    // MARK: - Internal helpers

    private func queryMonitorsRaw() throws -> [AerospaceMonitor] {
        guard let output = try runAerospaceWithOutput(args: [
            "list-monitors", "--json"
        ]) else { return [] }
        return try Self.decodeOrThrow(
            [AerospaceMonitor].self,
            from: output,
            label: "list-monitors"
        )
    }

    /// AeroSpace's daemon may not have stabilized monitor IDs on cold
    /// boot. Retry once after a 500ms backoff when the first call
    /// returns empty — matches the plan's first-launch-ordering note.
    private func queryMonitorsRawWithRetry() throws -> [AerospaceMonitor] {
        let first = try queryMonitorsRaw()
        if !first.isEmpty { return first }
        Thread.sleep(forTimeInterval: 0.5)
        return try queryMonitorsRaw()
    }

    // MARK: - CG bridge

    /// Build `CGDirectDisplayID → (frame, stableUUID)` snapshot.
    static func cgDisplaysByID() -> [CGDirectDisplayID: (CGRect, String)] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [:] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        var out: [CGDirectDisplayID: (CGRect, String)] = [:]
        for id in ids {
            let bounds = CGDisplayBounds(id)
            let uuid = Self.stableUUID(for: id) ?? ""
            out[id] = (bounds, uuid)
        }
        return out
    }

    /// Same shape as DisplayTopology.stableUUID — duplicated here to
    /// avoid a circular module dependency (DisplayTopology depends on
    /// WorkspaceState).
    static func stableUUID(for id: CGDirectDisplayID) -> String? {
        guard let cf = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
        let uuid = cf.takeRetainedValue()
        let str  = CFUUIDCreateString(nil, uuid)
        return str as String?
    }

    /// Best-effort match: AeroSpace's `monitor-name` does not always equal
    /// `NSScreen.localizedName`, and AeroSpace doesn't (currently) expose
    /// CGDirectDisplayID directly. Strategy:
    ///   1. If only one CG display, return it.
    ///   2. Otherwise iterate CG displays in id order — AeroSpace's
    ///      monitor-id 1 is usually the main display, matching CG's
    ///      enumeration order under typical setups.
    /// On a hot-plug edge case where this misorders, the spaces.json
    /// reconciler picks it up on next ws-topology run.
    static func cgMatch(
        monitorName: String,
        monitorId: Int,
        cgDisplays: [CGDirectDisplayID: (CGRect, String)]
    ) -> (DisplayInfo.Frame, String) {
        let ordered = cgDisplays.keys.sorted()
        guard !ordered.isEmpty else {
            return (DisplayInfo.Frame(x: 0, y: 0, w: 0, h: 0), "")
        }
        let pickIndex = max(0, min(monitorId - 1, ordered.count - 1))
        let id = ordered[pickIndex]
        let (rect, uuid) = cgDisplays[id]!
        let frame = DisplayInfo.Frame(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            w: Double(rect.size.width),
            h: Double(rect.size.height)
        )
        return (frame, uuid)
    }

    static func uuidForMonitor(
        id: Int,
        monitors: [AerospaceMonitor],
        cgDisplays: [CGDirectDisplayID: (CGRect, String)]
    ) -> String {
        guard let mon = monitors.first(where: { $0.monitorId == id }) else {
            return ""
        }
        let (_, uuid) = cgMatch(
            monitorName: mon.monitorName,
            monitorId: mon.monitorId,
            cgDisplays: cgDisplays
        )
        return uuid
    }

    // MARK: - Process helpers

    private func runAerospace(args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: data, encoding: .utf8) ?? "unknown error"
            throw WindowManagerError.commandFailed(
                "aerospace \(args.joined(separator: " ")): \(err)"
            )
        }
    }

    private func runAerospaceWithOutput(args: [String]) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decode JSON output via a typed model. Wraps JSONDecoder errors in
    /// `.parseError` with the command label for diagnostic clarity.
    /// Exposed for fixture tests via `Self.`.
    static func decodeOrThrow<T: Decodable>(
        _ type: T.Type,
        from output: String,
        label: String
    ) throws -> T {
        guard let data = output.data(using: .utf8) else {
            throw WindowManagerError.parseError("\(label): not utf8")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw WindowManagerError.parseError("\(label): \(error)")
        }
    }
}

// MARK: - AeroSpace JSON shapes
//
// Aerospace's --json output uses kebab-case keys. We decode through
// these private value types and project onto the protocol's
// camel-case wire types. All fields beyond the structural minimum are
// Optional to survive version drift between aerospace point releases.

struct AerospaceMonitor: Decodable, Sendable {
    let monitorId: Int
    let monitorName: String

    enum CodingKeys: String, CodingKey {
        case monitorId = "monitor-id"
        case monitorName = "monitor-name"
    }

    /// Internal memberwise init kept here (not in extension) because
    /// Swift forbids extension inits from assigning `let` properties.
    /// Exists to support unit tests that exercise `uuidForMonitor` with
    /// synthetic monitor lists.
    init(monitorId: Int, monitorName: String) {
        self.monitorId = monitorId
        self.monitorName = monitorName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.monitorId = try c.decode(Int.self, forKey: .monitorId)
        self.monitorName = try c.decode(String.self, forKey: .monitorName)
    }
}

struct AerospaceWorkspace: Decodable, Sendable {
    let workspace: String
    let monitorId: Int
    let monitorName: String?

    enum CodingKeys: String, CodingKey {
        case workspace
        case monitorId = "monitor-id"
        case monitorName = "monitor-name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.workspace = try c.decode(String.self, forKey: .workspace)
        // `--focused` output may omit monitor-id when no displays —
        // default to 1 for safety.
        self.monitorId = (try? c.decode(Int.self, forKey: .monitorId)) ?? 1
        self.monitorName = try? c.decode(String.self, forKey: .monitorName)
    }
}

struct AerospaceWindow: Decodable, Sendable {
    let windowId: Int
    let appName: String?
    let appBundleId: String?
    let windowTitle: String?
    let workspace: String?
    let monitorId: Int?

    enum CodingKeys: String, CodingKey {
        case windowId = "window-id"
        case appName = "app-name"
        case appBundleId = "app-bundle-id"
        case windowTitle = "window-title"
        case workspace
        case monitorId = "monitor-id"
    }
}
