import Foundation
import WorkspaceState

/// The "real" service. Reads spaces.json for identity (name / icon /
/// color), joins it against aerospace's live workspaces, and spawns the
/// focus / send helper scripts.
///
/// Paths are computed once at init from a `Paths` value so a test can
/// point the whole service at a sandbox directory if it ever needs the
/// production code path (e.g. integration tests).
final class ProductionWorkspaceService: WorkspaceService {
    struct Paths {
        let wsConfig: URL
    }

    private let paths: Paths
    private let windowManager: WindowManager

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

    // MARK: - Fire-and-forget helper

    func spawnSend(slot: Int) { spawnHelper(name: "ws-send-follow", arg: String(slot)) }

    // MARK: - Internals

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

        return .init(wsConfig: wsConfig)
    }
}
