import Foundation

public enum WorkspaceStateError: Error, CustomStringConvertible {
    case configNotFound(URL)
    case readFailed(URL, underlying: Error)
    case decodeFailed(URL, underlying: Error)
    case writeFailed(URL, underlying: Error)

    public var description: String {
        switch self {
        case .configNotFound(let url):
            return "spaces.json not found at \(url.path)"
        case .readFailed(let url, let err):
            return "failed reading \(url.path): \(err)"
        case .decodeFailed(let url, let err):
            return "failed decoding \(url.path): \(err)"
        case .writeFailed(let url, let err):
            return "failed writing \(url.path): \(err)"
        }
    }
}

/// Reads and writes the user's `spaces.json`. The store understands both v1 and
/// v2 on read (v1 is auto-promoted in memory via the same logic the Migration
/// uses). Writes always produce v2.
///
/// Atomic-mv contract matches `on-space-changed.sh:84-93`: write to a sibling
/// temp file in the same directory, then `rename` over the target so readers
/// never observe a half-written file.
public final class WorkspaceStateStore {
    public let configURL: URL

    public init(configURL: URL) {
        self.configURL = configURL
    }

    public convenience init(homeRelativePath: String = ".config/workspace/spaces.json") {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.init(configURL: home.appendingPathComponent(homeRelativePath))
    }

    public func load() throws -> WorkspaceConfig {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw WorkspaceStateError.configNotFound(configURL)
        }
        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            throw WorkspaceStateError.readFailed(configURL, underlying: error)
        }

        do {
            return try decode(data: data)
        } catch let err as WorkspaceStateError {
            throw err
        } catch {
            throw WorkspaceStateError.decodeFailed(configURL, underlying: error)
        }
    }

    public func decode(data: Data) throws -> WorkspaceConfig {
        guard let raw = try JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        ) as? [String: Any] else {
            throw WorkspaceStateError.decodeFailed(
                configURL,
                underlying: MigrationError.malformedJSON
            )
        }

        let version = (raw["version"] as? Int) ?? 1
        let palette = raw["palette"] as? String
        let theme   = raw["theme"] as? String
        let spaces  = (raw["spaces"] as? [String: Any]) ?? [:]

        // Extract a deterministic slot id from any of: v2 integer-string keys
        // ("1", "2", …), v3 `_unassigned:slot_<N>` keys, or v3 composite
        // `<uuid>:slot<N>` keys (where the workspaceName follows the
        // "slot<N>" convention). Fall back to sequential assignment for
        // user-renamed v3 workspaces whose names don't carry an ordinal.
        func extractSlotId(key: String, dict: [String: Any]) -> Int? {
            if let n = Int(key) { return n }
            // v3 key shapes: `<uuid>:slot<N>` and `_unassigned:slot<N>`.
            // Prefer workspaceName because it survives display-UUID changes
            // (key is rewritten by the encoder using workspaceName + uuid).
            if let workspaceName = dict["workspaceName"] as? String,
               workspaceName.hasPrefix("slot"),
               let n = Int(workspaceName.dropFirst("slot".count)) {
                return n
            }
            if let colon = key.firstIndex(of: ":") {
                let name = key[key.index(after: colon)...]
                if name.hasPrefix("slot"),
                   let n = Int(name.dropFirst("slot".count)) {
                    return n
                }
            }
            return nil
        }

        let orderedKeys = spaces.keys.sorted { (lhs, rhs) -> Bool in
            let lDict = (spaces[lhs] as? [String: Any]) ?? [:]
            let rDict = (spaces[rhs] as? [String: Any]) ?? [:]
            let l = extractSlotId(key: lhs, dict: lDict) ?? .max
            let r = extractSlotId(key: rhs, dict: rDict) ?? .max
            return l < r
        }

        var slots: [WorkspaceSlot] = []
        var nextSyntheticId = 1
        for key in orderedKeys {
            guard let dict = spaces[key] as? [String: Any] else { continue }
            let id: Int
            if let extracted = extractSlotId(key: key, dict: dict) {
                id = extracted
                nextSyntheticId = max(nextSyntheticId, extracted + 1)
            } else {
                id = nextSyntheticId
                nextSyntheticId += 1
            }
            let name  = (dict["name"] as? String) ?? "ws\(id)"
            let color = (dict["color"] as? String) ?? "#cdd6f4"
            let stableLabel = (dict["stableLogicalLabel"] as? String) ?? name

            let iconSpec: IconSpec
            if let iconDict = dict["iconSpec"] as? [String: Any] {
                iconSpec = WorkspaceStateStore.decodeSpec(from: iconDict)
            } else {
                let legacy = (dict["icon"] as? String) ?? ""
                iconSpec = Migration.deriveIconSpec(fromLegacy: legacy, name: name)
            }

            let displayUUID = (dict["displayUUID"] as? String) ?? ""
            let workspaceName = (dict["workspaceName"] as? String) ?? "slot\(id)"

            slots.append(WorkspaceSlot(
                id: id,
                name: name,
                color: color,
                iconSpec: iconSpec,
                stableLogicalLabel: stableLabel,
                displayUUID: displayUUID,
                workspaceName: workspaceName
            ))
        }

        return WorkspaceConfig(version: version, palette: palette, theme: theme, slots: slots)
    }

    public static func decodeSpec(from dict: [String: Any]) -> IconSpec {
        let kindRaw = (dict["kind"] as? String) ?? "none"
        let kind    = IconKind(rawValue: kindRaw) ?? .none
        return IconSpec(
            kind: kind,
            symbolName:       dict["symbolName"]       as? String,
            codepoint:        dict["codepoint"]        as? String,
            fontFamily:       dict["fontFamily"]       as? String,
            fallbackSfSymbol: dict["fallbackSfSymbol"] as? String,
            fallbackText:     dict["fallbackText"]     as? String,
            userOverridden:   (dict["userOverridden"]  as? Bool) ?? false
        )
    }

    /// Atomic write: temp file in the same directory, then `rename`.
    public func save(_ config: WorkspaceConfig) throws {
        let payload = encodeJSON(config)
        let dir = configURL.deletingLastPathComponent()
        let tempURL = dir.appendingPathComponent(".spaces.json.\(UUID().uuidString)")

        do {
            try Data(payload.utf8).write(to: tempURL, options: .atomic)
            _ = try FileManager.default.replaceItemAt(configURL, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw WorkspaceStateError.writeFailed(configURL, underlying: error)
        }
    }

    public func encodeJSON(_ config: WorkspaceConfig) -> String {
        var root: [String: Any] = [
            "version": Migration.currentVersion,
        ]
        if let palette = config.palette { root["palette"] = palette }
        if let theme   = config.theme   { root["theme"]   = theme }

        var spacesObj: [String: Any] = [:]
        for slot in config.slots {
            // v3 composite key. Empty displayUUID means the slot hasn't
            // been reconciled against a live aerospace monitor yet — those
            // land in the `_unassigned:*` bucket so ws-topology can find
            // and resolve them on the next reconcile pass.
            let uuid = slot.displayUUID.isEmpty ? "_unassigned" : slot.displayUUID
            let workspaceName = slot.workspaceName.isEmpty
                ? "slot\(slot.id)"
                : slot.workspaceName
            let key = "\(uuid):\(workspaceName)"
            spacesObj[key] = [
                "name":               slot.name,
                "color":              slot.color,
                "iconSpec":           Migration.encode(spec: slot.iconSpec),
                "stableLogicalLabel": slot.stableLogicalLabel,
                "displayUUID":        uuid,
                "workspaceName":      workspaceName,
            ] as [String: Any]
        }
        root["spaces"] = spacesObj

        return Migration.render(root: root)
    }
}
