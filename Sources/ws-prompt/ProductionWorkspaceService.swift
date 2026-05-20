import Foundation
import WorkspaceState

/// The "real" service. Spawns yabai / ws, reads spaces.json.
/// SF Symbols are stored directly; Nerd Font map available for
/// cross-platform use. All Process invocations and FileManager
/// paths that used to be scattered across main.swift,
/// WorkspaceData.swift, and the controllers live here.
///
/// Paths are computed once at init from a `Paths` value so a test can
/// point the whole service at a sandbox directory if it ever needs the
/// production code path (e.g. integration tests).
final class ProductionWorkspaceService: WorkspaceService {
    struct Paths {
        // yabaiBinary retained only for the legacy `querySpaceCountSync`
        // path (still referenced by the read-side fallback during the
        // aerospace transition). All runtime mutation is gone.
        let yabaiBinary: String
        let wsBinary: String
        let wsConfig: URL
        let iconMap: URL
    }

    private let paths: Paths
    private let windowManager: WindowManager
    private var cachedIconMap: Set<String>?

    init(paths: Paths = .default,
         windowManager: WindowManager = WindowManagerFactory.create()) {
        self.paths = paths
        self.windowManager = windowManager
    }

    // MARK: - Sync reads

    func loadWorkspaces() -> [Workspace] {
        // Single yabai query for both the slot count AND the per-slot
        // display index. The display info is what lets the manage
        // overlay's optimistic pre-paint short-circuit without an
        // extra RPC at chord-commit time.
        let displayBySlot = querySpaceDisplays()
        let count = displayBySlot.keys.max() ?? 0
        let identities = readIdentities()
        return (1...max(count, 0)).map { idx in
            let id = identities[idx]
            return Workspace(
                index: idx,
                display: displayBySlot[idx] ?? 1,
                name: id?.name ?? "ws\(idx)",
                color: id?.color ?? "#7f8c8d",
                icon: id?.icon,
                iconKind: id?.iconKind ?? .none
            )
        }
    }

    /// Build a `[slot index → display index]` map from the window
    /// manager's space snapshot. Empty when the window manager is
    /// unreachable; the caller treats that as "no spaces" and renders
    /// an empty list.
    private func querySpaceDisplays() -> [Int: Int] {
        guard let spaces = try? windowManager.querySpaces() else { return [:] }
        var out: [Int: Int] = [:]
        for space in spaces { out[space.index] = space.display }
        return out
    }

    func focusedSpaceIndex() -> Int? {
        return try? windowManager.focusedSpaceIndex()
    }

    func listSnapshots() -> [String] {
        let out = runWsCapture(args: ["layout", "list"]) ?? ""
        return out.split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func iconResolvable(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        if name.unicodeScalars.count == 1 { return true }
        return iconMap().contains(name)
    }

    private var cachedIconCatalog: [IconCatalogEntry]?

    func iconCatalog() -> [IconCatalogEntry] {
        if let cached = cachedIconCatalog { return cached }
        guard let data = try? Data(contentsOf: paths.iconMap),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { cachedIconCatalog = []; return [] }

        var entries: [IconCatalogEntry] = []
        for (name, value) in obj where !name.hasPrefix("_") {
            guard let codepointStr = value as? String,
                  let glyph = Self.decodeCodepoint(codepointStr)
            else { continue }
            entries.append(IconCatalogEntry(sfName: name, glyph: glyph))
        }
        entries.sort { $0.sfName < $1.sfName }
        cachedIconCatalog = entries
        return entries
    }

    // MARK: - Async commands

    func runWs(args: [String], completion: @escaping (CommandResult) -> Void) {
        runCommandAsync(binary: paths.wsBinary, args: args, completion: completion)
    }

    // Phase 5: runYabai + runAdd retired. AeroSpace can't create or
    // destroy workspaces at runtime; ws-prompt's add / destroy verbs
    // surface a help message instead (see ManageController's
    // aerospaceMutationHelp). Read-only yabai queries that survive
    // until Phase 6 use querySpaceCountSync below.

    // MARK: - Fire-and-forget helpers

    func spawnFocus(slot: Int) { spawnHelper(name: "ws-focus", arg: String(slot)) }
    func spawnSend(slot: Int)  { spawnHelper(name: "ws-send-follow", arg: String(slot)) }

    func fireOptimisticPrePaint(newSlot: Int, oldSlot: Int, display: Int) {
        // Don't bother if it's a no-op (target == current).
        guard newSlot != oldSlot else { return }
        // Probe sketchybar via Homebrew paths — same shape as
        // resolveYabaiBinary. If sketchybar isn't on disk, we silently
        // skip; ws-focus will fire the same trigger later as a backstop.
        let sketchybar = ["/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        guard let bin = sketchybar else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: bin)
        task.arguments = [
            "--trigger", "workspace_changed",
            "WS_OPTIMISTIC_SID=\(newSlot)",
            "WS_OPTIMISTIC_OLD_SID=\(oldSlot)",
            "WS_OPTIMISTIC_DISPLAY=\(display)"
        ]
        do { try task.run() } catch { /* fall through; bash backstop fires later */ }
    }

    // MARK: - Internals

    private func iconMap() -> Set<String> {
        if let cached = cachedIconMap { return cached }
        guard let data = try? Data(contentsOf: paths.iconMap),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { cachedIconMap = []; return [] }
        // Documentation keys start with `_` (e.g. `_doc`) — exclude them.
        let keys = Set(obj.keys.filter { !$0.hasPrefix("_") })
        cachedIconMap = keys
        return keys
    }

    private struct IdentityRaw: Decodable {
        let name: String?
        let color: String?
        let iconSpec: IconSpec?
    }
    private struct IconSpec: Decodable {
        let kind: String?
        let codepoint: String?
        let symbolName: String?
        let fallbackSfSymbol: String?
    }
    private struct ResolvedIdentity {
        let name: String?
        let color: String?
        let icon: String?
        let iconKind: Workspace.IconKind
    }

    private func readIdentities() -> [Int: ResolvedIdentity] {
        guard let data = try? Data(contentsOf: paths.wsConfig) else { return [:] }
        struct Root: Decodable { let spaces: [String: IdentityRaw]? }
        guard let root = try? JSONDecoder().decode(Root.self, from: data),
              let raw = root.spaces else { return [:] }

        var out: [Int: ResolvedIdentity] = [:]
        for (key, value) in raw {
            guard let idx = Int(key) else { continue }
            let kind: Workspace.IconKind
            let glyph: String?
            switch value.iconSpec?.kind {
            case "nerdFont":
                kind = .nerdFont
                glyph = Self.decodeCodepoint(value.iconSpec?.codepoint)
                    ?? value.iconSpec?.fallbackSfSymbol
            case "sfSymbol":
                kind = .sfSymbol
                glyph = value.iconSpec?.symbolName
                    ?? value.iconSpec?.fallbackSfSymbol
            default:
                kind = .none
                glyph = nil
            }
            out[idx] = ResolvedIdentity(
                name: value.name,
                color: value.color,
                icon: glyph,
                iconKind: glyph == nil ? .none : kind
            )
        }
        return out
    }

    private static func decodeCodepoint(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.unicodeScalars.count == 1 { return raw }
        if raw.hasPrefix("\\u{"), raw.hasSuffix("}") {
            let hex = String(raw.dropFirst(3).dropLast())
            if let v = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(v) {
                return String(scalar)
            }
        }
        if raw.hasPrefix("\\u"), raw.count >= 6 {
            let hex = String(raw.dropFirst(2).prefix(4))
            if let v = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(v) {
                return String(scalar)
            }
        }
        return raw
    }

    // MARK: - Process helpers

    private func runCommandAsync(binary: String, args: [String],
                                 completion: @escaping (CommandResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.runCommandSync(binary: binary, args: args)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func runCommandSync(binary: String, args: [String]) -> CommandResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return CommandResult(success: false, output: "spawn failed: \(error)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return CommandResult(success: task.terminationStatus == 0, output: output)
    }

    private func runWsCapture(args: [String]) -> String? {
        let result = Self.runCommandSync(binary: paths.wsBinary, args: args)
        return result.success ? result.output : nil
    }

    private static func querySpaceCountSync(binary: String) -> Int {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = ["-m", "query", "--spaces"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run(); task.waitUntilExit() } catch { return 0 }
        guard task.terminationStatus == 0 else { return 0 }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return 0
        }
        return arr.count
    }

    private func spawnHelper(name: String, arg: String) {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/\(name)").path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = [arg]
        do { try task.run() } catch {
            FileHandle.standardError.write(Data(
                "ws-prompt: spawn \(name) failed: \(error)\n".utf8))
        }
    }
}

// MARK: - Path resolution

extension ProductionWorkspaceService.Paths {
    /// Build a Paths value from the live environment. yabai is probed
    /// against both Homebrew install locations; the rest are the fixed
    /// dotfiles locations. WS_CONFIG env var overrides spaces.json so
    /// the bash test harness can point at a fixture without monkey-
    /// patching the home directory.
    static var `default`: ProductionWorkspaceService.Paths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment

        let wsConfig: URL = {
            if let override = env["WS_CONFIG"], !override.isEmpty {
                return URL(fileURLWithPath: override)
            }
            return home.appendingPathComponent(".config/workspace/spaces.json")
        }()

        return .init(
            yabaiBinary: resolveYabaiBinary(),
            wsBinary: home.appendingPathComponent(".local/bin/ws").path,
            wsConfig: wsConfig,
            iconMap: home.appendingPathComponent(".config/workspace/lib/sf-to-nerd.json")
        )
    }

    /// yabai install paths vary (Apple-Silicon Homebrew, Intel Homebrew,
    /// or a user-installed binary). YABAI_BIN env var wins when set —
    /// the bash test harness uses this to point at the yabai-stub.
    private static func resolveYabaiBinary() -> String {
        if let override = ProcessInfo.processInfo.environment["YABAI_BIN"],
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        for path in ["/opt/homebrew/bin/yabai", "/usr/local/bin/yabai"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "yabai"  // last resort: rely on PATH
    }
}
