import Foundation
import WorkspaceState

/// The "real" service. Spawns aerospace / ws, reads spaces.json.
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
        // querySpaces() is the source of truth for which workspaces
        // currently exist. Identity (name / color / icon) joins from
        // spaces.json by WorkspaceTarget (displayUUID, workspaceName).
        // Empty list when aerospace is unreachable — the caller treats
        // that as "no workspaces" and renders an empty pill strip.
        let liveSpaces = (try? windowManager.querySpaces()) ?? []
        let identities = readIdentities()
        return liveSpaces.enumerated().map { (position, space) in
            let target = WorkspaceTarget(
                displayUUID: space.displayUUID,
                workspaceName: space.workspaceName
            )
            let id = identities[target]
            let ordinal = position + 1
            return Workspace(
                index: ordinal,
                display: space.display,
                name: id?.name ?? "ws\(ordinal)",
                color: id?.color ?? "#7f8c8d",
                icon: id?.icon,
                iconKind: id?.iconKind ?? .none
            )
        }
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
    // aerospaceMutationHelp). Read-only aerospace queries that survive
    // until Phase 6 use querySpaceCountSync below.

    // MARK: - Fire-and-forget helpers

    func spawnFocus(slot: Int) { spawnHelper(name: "ws-focus", arg: String(slot)) }
    func spawnSend(slot: Int)  { spawnHelper(name: "ws-send-follow", arg: String(slot)) }

    func fireOptimisticPrePaint(newSlot: Int, oldSlot: Int, display: Int) {
        // No-op when target == current. Sketchybar probe is defensive:
        // when the binary isn't on disk, skip silently — ws-focus fires
        // the same trigger later as a backstop.
        guard newSlot != oldSlot else { return }
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

    /// Build a `[WorkspaceTarget → ResolvedIdentity]` map from spaces.json.
    /// Joined against `querySpaces()` in `loadWorkspaces()` so live
    /// workspaces inherit their name / color / icon from the JSON
    /// identity layer. Empty when the file is missing / unreadable —
    /// callers fall back to per-position defaults.
    private func readIdentities() -> [WorkspaceTarget: ResolvedIdentity] {
        guard let data = try? Data(contentsOf: paths.wsConfig) else { return [:] }
        struct SlotRaw: Decodable {
            let name: String?
            let color: String?
            let iconSpec: IconSpec?
            let displayUUID: String?
            let workspaceName: String?
        }
        struct Root: Decodable { let spaces: [String: SlotRaw]? }
        guard let root = try? JSONDecoder().decode(Root.self, from: data),
              let raw = root.spaces else { return [:] }

        var out: [WorkspaceTarget: ResolvedIdentity] = [:]
        for (key, value) in raw {
            // v3 composite-key shape: "<uuid>:<workspaceName>". Prefer
            // explicit fields on the slot; fall back to splitting the
            // key if either is missing (defensive).
            let (keyUUID, keyName) = Self.splitCompositeKey(key)
            let uuid = (value.displayUUID?.isEmpty == false) ? value.displayUUID! : keyUUID
            let name = (value.workspaceName?.isEmpty == false) ? value.workspaceName! : keyName
            guard !uuid.isEmpty, !name.isEmpty else { continue }

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
            let target = WorkspaceTarget(displayUUID: uuid, workspaceName: name)
            out[target] = ResolvedIdentity(
                name: value.name,
                color: value.color,
                icon: glyph,
                iconKind: glyph == nil ? .none : kind
            )
        }
        return out
    }

    private static func splitCompositeKey(_ key: String) -> (uuid: String, name: String) {
        guard let colon = key.firstIndex(of: ":") else { return ("", "") }
        let uuid = String(key[..<colon])
        let name = String(key[key.index(after: colon)...])
        return (uuid, name)
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
    /// Build a Paths value from the live environment. WS_CONFIG env var
    /// overrides spaces.json so the bash test harness can point at a
    /// fixture without monkey-patching the home directory.
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
            wsBinary: home.appendingPathComponent(".local/bin/ws").path,
            wsConfig: wsConfig,
            iconMap: home.appendingPathComponent(".config/workspace/lib/sf-to-nerd.json")
        )
    }
}
