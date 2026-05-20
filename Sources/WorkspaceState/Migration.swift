import Foundation

public enum MigrationError: Error, CustomStringConvertible {
    case malformedJSON
    case missingSpaces
    case unsupportedVersion(Int)

    public var description: String {
        switch self {
        case .malformedJSON:           return "spaces.json is not valid JSON"
        case .missingSpaces:           return "spaces.json has no `spaces` object"
        case .unsupportedVersion(let v): return "unsupported spaces.json version: \(v)"
        }
    }
}

public struct MigrationResult: Equatable {
    /// True only when input was already at the latest schema (v3) and
    /// nothing changed. Kept as `alreadyV2` for source-compat with prior
    /// consumers; semantics now mean "already at current version".
    public let alreadyV2: Bool
    public let slotsTouched: Int
    /// Number of v2 slots that landed in the `_unassigned:*` bucket
    /// during v2 → v3 migration. Informational — ws-topology reconciles
    /// these on next startup by matching against live aerospace
    /// workspaces. Zero on a no-op migration.
    public let unassignedSlots: Int
    public let outputJSON: String

    public init(
        alreadyV2: Bool,
        slotsTouched: Int,
        unassignedSlots: Int = 0,
        outputJSON: String
    ) {
        self.alreadyV2 = alreadyV2
        self.slotsTouched = slotsTouched
        self.unassignedSlots = unassignedSlots
        self.outputJSON = outputJSON
    }
}

/// spaces.json schema migration. Chains v1 → v2 → v3 in a single call.
/// Preserves all unknown top-level keys (e.g. `_doc_*` comments) and all
/// unknown slot-level fields. Idempotent at every level.
public enum Migration {
    public static let currentVersion = 3
    public static let defaultNerdFontFamily = "JetBrainsMono Nerd Font"

    public static func migrate(jsonData: Data) throws -> MigrationResult {
        guard let raw = try JSONSerialization.jsonObject(
            with: jsonData,
            options: [.fragmentsAllowed]
        ) as? [String: Any] else {
            throw MigrationError.malformedJSON
        }

        var root = raw
        let version = (root["version"] as? Int) ?? 1
        guard version >= 1 && version <= currentVersion else {
            throw MigrationError.unsupportedVersion(version)
        }

        guard root["spaces"] is [String: Any] else {
            throw MigrationError.missingSpaces
        }

        // Step 1: v1 → v2 — add iconSpec, stableLogicalLabel, name/color
        // defaults. Operates on slots whose keys are still integer strings.
        var touched = 0
        if version <= 2 {
            let v2 = migrateV1ToV2(root: root, alreadyV2: version == 2)
            root = v2.root
            touched = v2.touched
        }

        // Step 2: v2 → v3 — rewrite integer-string slot keys to
        // `_unassigned:slot_<N>` composites and add displayUUID +
        // workspaceName fields. ws-topology reconciles _unassigned
        // entries against live aerospace workspaces on next startup.
        var unassigned = 0
        if version <= 3 {
            let v3 = migrateV2ToV3(root: root)
            root = v3.root
            unassigned = v3.unassigned
        }

        root["version"] = currentVersion

        let outputJSON = render(root: root)
        return MigrationResult(
            alreadyV2: version == currentVersion && touched == 0 && unassigned == 0,
            slotsTouched: touched,
            unassignedSlots: unassigned,
            outputJSON: outputJSON
        )
    }

    // MARK: - Per-version stages

    struct V1ToV2 {
        var root: [String: Any]
        var touched: Int
    }

    static func migrateV1ToV2(root: [String: Any], alreadyV2: Bool) -> V1ToV2 {
        var root = root
        guard let spaces = root["spaces"] as? [String: Any] else {
            return V1ToV2(root: root, touched: 0)
        }

        var migratedSpaces: [String: Any] = [:]
        var touched = 0
        let orderedKeys = spaces.keys.sorted { lhs, rhs in
            (Int(lhs) ?? .max) < (Int(rhs) ?? .max)
        }

        for key in orderedKeys {
            guard let slot = spaces[key] as? [String: Any] else { continue }
            let result = migrateSlot(key: key, slot: slot, alreadyV2: alreadyV2)
            migratedSpaces[key] = result.slot
            if result.touched { touched += 1 }
        }

        root["spaces"] = migratedSpaces
        return V1ToV2(root: root, touched: touched)
    }

    struct V2ToV3 {
        var root: [String: Any]
        var unassigned: Int
    }

    /// v2 → v3: composite-key migration. Integer-string keys ("1", "2", …)
    /// rewrite to `_unassigned:slot_<N>` so ws-topology can reconcile them
    /// against live aerospace workspaces. Keys that already look like v3
    /// composites are passed through. Each slot gains `displayUUID` and
    /// `workspaceName` fields (empty + synthesized name for unassigned
    /// entries; preserved verbatim for already-v3 entries).
    static func migrateV2ToV3(root: [String: Any]) -> V2ToV3 {
        var root = root
        guard let spaces = root["spaces"] as? [String: Any] else {
            return V2ToV3(root: root, unassigned: 0)
        }

        var migratedSpaces: [String: Any] = [:]
        var unassigned = 0
        for (key, value) in spaces {
            guard var slot = value as? [String: Any] else { continue }

            // Already-v3 composite key: pass through. Backfill missing
            // displayUUID/workspaceName fields against the key but do NOT
            // recount existing _unassigned entries — the counter measures
            // freshly-migrated v2 slots, so idempotent v3→v3 passes report
            // zero.
            if key.contains(":") {
                let parts = key.split(separator: ":", maxSplits: 1)
                let uuidPart = String(parts.first ?? "")
                let namePart = parts.count > 1 ? String(parts[1]) : ""
                if slot["displayUUID"] == nil { slot["displayUUID"] = uuidPart }
                if slot["workspaceName"] == nil { slot["workspaceName"] = namePart }
                migratedSpaces[key] = slot
                continue
            }

            // v2 integer-string key → `_unassigned:slot<N>` composite. The
            // `_unassigned` prefix is a sentinel; ws-topology reconciles
            // these on next startup against live aerospace workspaces.
            // No extra underscore — keeps the key shape aligned with the
            // workspaceName convention (`slot<N>`), so encoder + migrator
            // agree on `"<uuid>:<workspaceName>"`.
            guard let n = Int(key) else { continue }
            let synthesizedName = "slot\(n)"
            let newKey = "_unassigned:\(synthesizedName)"
            slot["displayUUID"] = "_unassigned"
            slot["workspaceName"] = synthesizedName
            migratedSpaces[newKey] = slot
            unassigned += 1
        }

        root["spaces"] = migratedSpaces
        return V2ToV3(root: root, unassigned: unassigned)
    }

    struct SlotMigration {
        let slot: [String: Any]
        let touched: Bool
    }

    static func migrateSlot(key: String, slot: [String: Any], alreadyV2: Bool) -> SlotMigration {
        var out = slot
        var touched = false

        let name  = (out["name"] as? String) ?? "ws\(key)"
        let color = (out["color"] as? String) ?? "#cdd6f4"

        if out["iconSpec"] == nil {
            let legacy = (out["icon"] as? String) ?? ""
            let spec = deriveIconSpec(fromLegacy: legacy, name: name)
            out["iconSpec"] = encode(spec: spec)
            touched = true
        }

        if out["stableLogicalLabel"] == nil {
            out["stableLogicalLabel"] = name
            touched = true
        }

        out["name"]  = name
        out["color"] = color

        if !alreadyV2 { out.removeValue(forKey: "icon") }

        return SlotMigration(slot: out, touched: touched)
    }

    public static func deriveIconSpec(fromLegacy legacy: String, name: String) -> IconSpec {
        let trimmed = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackText = SfSymbolFallbacks.textFallback(forSlotName: name)
        let fallbackSf   = SfSymbolFallbacks.symbol(forSlotName: name)

        if trimmed.isEmpty {
            return IconSpec(
                kind: .none,
                fallbackSfSymbol: fallbackSf,
                fallbackText: fallbackText,
                userOverridden: false
            )
        }

        let scalars = Array(trimmed.unicodeScalars)
        if scalars.count == 1, IconCodepoint.isPrivateUseArea(scalars[0]) {
            return IconSpec(
                kind: .nerdFont,
                codepoint: IconCodepoint.encode(scalars[0]),
                fontFamily: defaultNerdFontFamily,
                fallbackSfSymbol: fallbackSf,
                fallbackText: fallbackText,
                userOverridden: false
            )
        }

        return IconSpec(
            kind: .text,
            fallbackText: trimmed,
            userOverridden: false
        )
    }

    public static func encode(spec: IconSpec) -> [String: Any] {
        var dict: [String: Any] = [
            "kind": spec.kind.rawValue,
            "userOverridden": spec.userOverridden,
        ]
        if let v = spec.symbolName        { dict["symbolName"]       = v }
        if let v = spec.codepoint         { dict["codepoint"]        = v }
        if let v = spec.fontFamily        { dict["fontFamily"]       = v }
        if let v = spec.fallbackSfSymbol  { dict["fallbackSfSymbol"] = v }
        if let v = spec.fallbackText      { dict["fallbackText"]     = v }
        return dict
    }

    // MARK: - Deterministic pretty-printer
    //
    // JSONSerialization with .sortedKeys would alpha-sort everything, which puts
    // "10" before "2" inside `.spaces`. We need numerical ordering for slot keys
    // and alpha ordering everywhere else, so we render by hand.

    public static func render(root: [String: Any]) -> String {
        renderObject(root, indent: 0, isSpacesMap: false) + "\n"
    }

    /// Deterministic sort for the `spaces` map. v2 (integer-string) keys
    /// sort numerically; v3 (composite `<uuid>:<name>`) keys group by
    /// displayUUID then by workspaceName. v3 `_unassigned:*` entries sort
    /// before real-UUID entries by virtue of `_` < ASCII digits. Within
    /// `_unassigned:slot_<N>`, sort by N (not by string, so slot_10 lands
    /// after slot_9). Stable, jq-friendly.
    static func spacesKeyOrder(_ lhs: String, _ rhs: String) -> Bool {
        let l = spacesSortKey(lhs)
        let r = spacesSortKey(rhs)
        return l < r
    }

    /// Tuple sort key: (group, primaryString, slotSuffix, originalKey).
    /// - group 0: legacy integer-string keys (sorted by Int value)
    /// - group 1: `_unassigned:slot<N>` (sorted by N)
    /// - group 2: composite `<uuid>:<name>` (sorted lex by uuid then name)
    static func spacesSortKey(_ key: String) -> (Int, String, Int, String) {
        if let n = Int(key) {
            return (0, "", n, key)
        }
        if key.hasPrefix("_unassigned:slot"),
           let n = Int(key.dropFirst("_unassigned:slot".count)) {
            return (1, "_unassigned", n, key)
        }
        if let colon = key.firstIndex(of: ":") {
            let uuid = String(key[..<colon])
            let name = String(key[key.index(after: colon)...])
            return (2, uuid + "\u{1F}" + name, 0, key)
        }
        return (3, key, 0, key)
    }

    static func renderObject(
        _ obj: [String: Any],
        indent: Int,
        isSpacesMap: Bool
    ) -> String {
        if obj.isEmpty { return "{}" }
        let keys = isSpacesMap
            ? obj.keys.sorted(by: spacesKeyOrder)
            : obj.keys.sorted()
        let pad   = String(repeating: " ", count: indent + 2)
        let close = String(repeating: " ", count: indent)
        var lines: [String] = []
        for (i, key) in keys.enumerated() {
            let value = obj[key] ?? NSNull()
            let isLast = (i == keys.count - 1)
            let valueStr = renderValue(value, indent: indent + 2, currentKey: key)
            lines.append("\(pad)\"\(escape(key))\": \(valueStr)\(isLast ? "" : ",")")
        }
        return "{\n" + lines.joined(separator: "\n") + "\n\(close)}"
    }

    static func renderArray(_ arr: [Any], indent: Int) -> String {
        if arr.isEmpty { return "[]" }
        let pad   = String(repeating: " ", count: indent + 2)
        let close = String(repeating: " ", count: indent)
        var lines: [String] = []
        for (i, value) in arr.enumerated() {
            let isLast = (i == arr.count - 1)
            let valueStr = renderValue(value, indent: indent + 2, currentKey: nil)
            lines.append("\(pad)\(valueStr)\(isLast ? "" : ",")")
        }
        return "[\n" + lines.joined(separator: "\n") + "\n\(close)]"
    }

    static func renderValue(_ value: Any, indent: Int, currentKey: String?) -> String {
        if value is NSNull { return "null" }
        if let b = value as? Bool { return b ? "true" : "false" }
        if let n = value as? NSNumber {
            // Distinguish booleans from numbers — NSNumber bridges Bool, but the
            // `value as? Bool` check above already caught true Bool instances.
            return numberString(n)
        }
        if let s = value as? String { return "\"\(escape(s))\"" }
        if let a = value as? [Any]  { return renderArray(a, indent: indent) }
        if let o = value as? [String: Any] {
            let isSpaces = (currentKey == "spaces")
            return renderObject(o, indent: indent, isSpacesMap: isSpaces)
        }
        return "null"
    }

    static func numberString(_ n: NSNumber) -> String {
        // CFNumber type detection: integer-looking values render without trailing .0.
        let str = n.stringValue
        return str
    }

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "\"":  out += "\\\""
            case "\\":  out += "\\\\"
            case "\n":  out += "\\n"
            case "\r":  out += "\\r"
            case "\t":  out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else {
                    out += String(ch)
                }
            }
        }
        return out
    }
}
