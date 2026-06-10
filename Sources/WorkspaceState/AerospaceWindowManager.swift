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
///   `CGDisplayCreateUUIDFromDisplayID(…)` UUID. AeroSpace's `--json`
///   doesn't expose frames or CGDirectDisplayIDs, so the bridge is a
///   positional heuristic: monitor-id N maps to the N-th CG display in
///   sorted-id order (see `cgUUID(monitorId:cgDisplays:)`).
///
/// Workspaces are declared statically in aerospace.toml; runtime
/// create/destroy isn't supported. ws-prompt surfaces an edit-then-
/// reload help message for those flows.
public final class AerospaceWindowManager: WindowManager {
    public let binaryPath: String

    public init(binaryPath: String? = nil) {
        self.binaryPath = binaryPath ?? "/opt/homebrew/bin/aerospace"
    }

    // MARK: - Window Operations

    public func focusWindow(id: Int) throws {
        try runAerospace(args: ["focus", "--window-id", "\(id)"])
    }

    // MARK: - Read-side queries

    public func queryWindows() throws -> [WindowInfo] {
        guard let output = try runAerospaceWithOutput(args: [
            "list-windows", "--all", "--json"
        ]) else { return [] }
        let parsed = try Self.decodeOrThrow(
            [AerospaceWindow].self,
            from: output,
            label: "list-windows --all"
        )
        return parsed.map(Self.windowInfo(from:))
    }

    /// Pure projection from the decoded wire type — split out so tests
    /// can pin the mapping without a live daemon.
    static func windowInfo(from w: AerospaceWindow) -> WindowInfo {
        WindowInfo(
            id: w.windowId,
            app: w.appName ?? w.appBundleId ?? "Unknown",
            title: w.windowTitle ?? "",
            workspace: w.workspace ?? "",
            display: w.monitorId ?? 1
        )
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

        return parsed.map { w in
            SpaceInfo(
                display: w.monitorId,
                displayUUID: Self.uuidForMonitor(
                    id: w.monitorId,
                    monitors: monitors,
                    cgDisplays: cgIndex
                ),
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

    // MARK: - CG bridge

    /// Build `CGDirectDisplayID → stableUUID` snapshot.
    static func cgDisplaysByID() -> [CGDirectDisplayID: String] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [:] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        var out: [CGDirectDisplayID: String] = [:]
        for id in ids {
            out[id] = Self.stableUUID(for: id) ?? ""
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

    /// Best-effort match: AeroSpace's `--json` exposes neither display
    /// frames nor CGDirectDisplayIDs, so the only available bridge is
    /// positional — AeroSpace's monitor-id 1 is usually the main display,
    /// matching CG's sorted-id enumeration order under typical setups.
    /// On a hot-plug edge case where this misorders, the spaces.json
    /// reconciler picks it up on next ws-topology run.
    static func cgUUID(
        monitorId: Int,
        cgDisplays: [CGDirectDisplayID: String]
    ) -> String {
        let ordered = cgDisplays.keys.sorted()
        guard !ordered.isEmpty else { return "" }
        let pickIndex = max(0, min(monitorId - 1, ordered.count - 1))
        return cgDisplays[ordered[pickIndex]]!
    }

    /// Resolve a monitor-id to its CG display UUID; "" when the id isn't
    /// in the live monitor list — keeps callers safe under hot-plug races.
    static func uuidForMonitor(
        id: Int,
        monitors: [AerospaceMonitor],
        cgDisplays: [CGDirectDisplayID: String]
    ) -> String {
        guard monitors.contains(where: { $0.monitorId == id }) else {
            return ""
        }
        return cgUUID(monitorId: id, cgDisplays: cgDisplays)
    }

    // MARK: - Process helpers
    //
    // Both helpers drain the pipe BEFORE waitUntilExit. A pipe buffer
    // holds ~64KB; waiting first deadlocks once the child fills it and
    // blocks on write(2) — `list-windows --all --json` can exceed that
    // with a few hundred windows or long titles.

    private func runAerospace(args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let err = String(data: data, encoding: .utf8) ?? "unknown error"
            throw WindowManagerError.commandFailed(
                "aerospace \(args.joined(separator: " ")): \(err)"
            )
        }
    }

    /// nil on nonzero exit — callers render "no workspaces / windows" for
    /// a down daemon. The child's stderr passes through to ours so the
    /// diagnostic isn't swallowed.
    private func runAerospaceWithOutput(args: [String]) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.standardError
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
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

    enum CodingKeys: String, CodingKey {
        case workspace
        case monitorId = "monitor-id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.workspace = try c.decode(String.self, forKey: .workspace)
        // `--focused` output may omit monitor-id when no displays —
        // default to 1 for safety.
        self.monitorId = (try? c.decode(Int.self, forKey: .monitorId)) ?? 1
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
