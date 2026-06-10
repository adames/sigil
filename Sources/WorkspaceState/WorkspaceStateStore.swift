import Foundation

public enum WorkspaceStateError: Error, CustomStringConvertible {
    case configNotFound(URL)
    case readFailed(URL, underlying: Error)
    case decodeFailed(URL, underlying: Error)

    public var description: String {
        switch self {
        case .configNotFound(let url):
            return "spaces.json not found at \(url.path)"
        case .readFailed(let url, let err):
            return "failed reading \(url.path): \(err)"
        case .decodeFailed(let url, let err):
            return "failed decoding \(url.path): \(err)"
        }
    }
}

/// Reads the user's `spaces.json`. v3-only (composite-key) since the
/// AeroSpace migration shipped — v1/v2 inputs raise
/// `MigrationError.unsupportedVersion(_)`, which the caller is expected
/// to surface as a doctor message.
///
/// Read-only by design: all writes to spaces.json go through the `ws`
/// CLI's atomic-mv idiom, never through Swift.
public final class WorkspaceStateStore {
    public let configURL: URL

    public init(configURL: URL) {
        self.configURL = configURL
    }

    public func load() throws -> WorkspaceConfig {
        // Read first, classify after — an exists-check would race the
        // CLI's atomic-rename writers.
        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch let err as NSError
            where err.domain == NSCocoaErrorDomain
               && err.code == NSFileReadNoSuchFileError {
            throw WorkspaceStateError.configNotFound(configURL)
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

        guard let version = raw["version"] as? Int else {
            throw WorkspaceStateError.decodeFailed(
                configURL,
                underlying: MigrationError.missingVersion
            )
        }
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
        // the user sees on disk + in the pill strip. Any per-workspace
        // ordinal a UI consumer wants comes from this sort position.
        let orderedKeys = spaces.keys.sorted(by: Migration.spacesKeyOrder)

        var slots: [WorkspaceSlot] = []
        for (position, key) in orderedKeys.enumerated() {
            guard let dict = spaces[key] as? [String: Any] else { continue }
            let positionalFallback = "ws\(position + 1)"
            let name  = (dict["name"] as? String) ?? positionalFallback
            let color = (dict["color"] as? String) ?? "#cdd6f4"
            let stableLabel = (dict["stableLogicalLabel"] as? String) ?? name
            let iconSpec = (dict["iconSpec"] as? [String: Any]).map(Self.decodeSpec)
                ?? IconSpec(kind: .none, userOverridden: false)
            let displayUUID = (dict["displayUUID"] as? String) ?? ""
            let workspaceName = (dict["workspaceName"] as? String) ?? ""

            // Both identity fields are required under v3 (WorkspaceSlot's
            // contract); a slot without them can't be matched by anything,
            // so skip it rather than fabricate an empty identity.
            guard !displayUUID.isEmpty, !workspaceName.isEmpty else { continue }

            slots.append(WorkspaceSlot(
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

}
