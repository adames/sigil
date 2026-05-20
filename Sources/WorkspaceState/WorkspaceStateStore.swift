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

/// Reads and writes the user's `spaces.json`. v3-only (composite-key) since
/// the AeroSpace migration shipped — v1/v2 inputs raise
/// `MigrationError.unsupportedVersion(_)` via `Migration.migrate(jsonData:)`,
/// which the caller is expected to surface as a doctor message.
///
/// Atomic-mv contract matches `on-space-changed.sh`'s write idiom: write to
/// a sibling temp file in the same directory, then `rename` over the target
/// so readers never observe a half-written file.
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
        guard version == Migration.currentVersion else {
            throw WorkspaceStateError.decodeFailed(
                configURL,
                underlying: MigrationError.unsupportedVersion(version)
            )
        }

        let palette = raw["palette"] as? String
        let theme   = raw["theme"] as? String
        let spaces  = (raw["spaces"] as? [String: Any]) ?? [:]

        // v3 keys are composite `<displayUUID>:<workspaceName>`. Sort by
        // the same tuple the renderer uses so decode order matches what
        // the user sees on disk + in the pill strip.
        let orderedKeys = spaces.keys.sorted(by: Migration.spacesKeyOrder)

        var slots: [WorkspaceSlot] = []
        for (position, key) in orderedKeys.enumerated() {
            guard let dict = spaces[key] as? [String: Any] else { continue }
            let id = position + 1  // 1-based ordinal; legacy field, due to retire
            let name  = (dict["name"] as? String) ?? "ws\(id)"
            let color = (dict["color"] as? String) ?? "#cdd6f4"
            let stableLabel = (dict["stableLogicalLabel"] as? String) ?? name
            let iconSpec = (dict["iconSpec"] as? [String: Any]).map(Self.decodeSpec)
                ?? IconSpec(kind: .none, userOverridden: false)
            let displayUUID = (dict["displayUUID"] as? String) ?? ""
            let workspaceName = (dict["workspaceName"] as? String) ?? ""

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
            // v3 composite key from (displayUUID, workspaceName). Both
            // fields are required under v3; an empty value indicates a
            // construction bug and surfaces as an invalid `:name` /
            // `uuid:` key the renderer will faithfully output (and the
            // loader will reject on read).
            let key = "\(slot.displayUUID):\(slot.workspaceName)"
            spacesObj[key] = [
                "name":               slot.name,
                "color":              slot.color,
                "iconSpec":           Migration.encode(spec: slot.iconSpec),
                "stableLogicalLabel": slot.stableLogicalLabel,
                "displayUUID":        slot.displayUUID,
                "workspaceName":      slot.workspaceName,
            ] as [String: Any]
        }
        root["spaces"] = spacesObj

        return Migration.render(root: root)
    }
}
