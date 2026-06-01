import Foundation

public enum MigrationError: Error, CustomStringConvertible {
    case malformedJSON
    case missingSpaces
    case unsupportedVersion(Int)

    public var description: String {
        switch self {
        case .malformedJSON:           return "spaces.json is not valid JSON"
        case .missingSpaces:           return "spaces.json has no `spaces` object"
        case .unsupportedVersion(let v): return "unsupported spaces.json version: \(v) (only v\(Migration.currentVersion) is accepted)"
        }
    }
}

public struct MigrationResult: Equatable {
    /// The validated, canonically-rendered spaces.json output. Re-rendering
    /// produces a jq-friendly deterministic key order without semantic changes.
    public let outputJSON: String

    public init(outputJSON: String) {
        self.outputJSON = outputJSON
    }
}

/// spaces.json v3 validator + canonical pretty-printer.
///
/// The v1 → v2 and v2 → v3 transformation code was retired after the
/// AeroSpace migration shipped. `migrate(jsonData:)` is now a validator:
/// it requires version == currentVersion (v3), re-renders the JSON with
/// deterministic key ordering, and returns the canonical bytes. v1 or v2
/// inputs throw `.unsupportedVersion(_)`.
public enum Migration {
    public static let currentVersion = 3
    public static let defaultNerdFontFamily = "JetBrainsMono Nerd Font"

    public static func migrate(jsonData: Data) throws -> MigrationResult {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(
                with: jsonData,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw MigrationError.malformedJSON
        }
        guard let raw = parsed as? [String: Any] else {
            throw MigrationError.malformedJSON
        }

        let version = (raw["version"] as? Int) ?? 1
        guard version == currentVersion else {
            throw MigrationError.unsupportedVersion(version)
        }
        guard raw["spaces"] is [String: Any] else {
            throw MigrationError.missingSpaces
        }

        return MigrationResult(outputJSON: render(root: raw))
    }

    // MARK: - IconSpec helpers
    //
    // The `deriveIconSpec(fromLegacy:name:)` builder retired with the
    // v1/v2 transformation paths — under v3 every slot ships its own
    // iconSpec object directly. `encode(spec:)` survives because the
    // store's writer still serializes WorkspaceSlot → JSON through it.

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
    // JSONSerialization with .sortedKeys would alpha-sort everything,
    // which puts "10" before "2" inside `.spaces`. v3 keys are composite
    // `<displayUUID>:<workspaceName>` — group by displayUUID, then by
    // workspaceName lexically. Stable, jq-friendly.

    public static func render(root: [String: Any]) -> String {
        renderObject(root, indent: 0, isSpacesMap: false) + "\n"
    }

    /// Deterministic sort for the `spaces` map.
    /// Composite keys `<displayUUID>:<workspaceName>` group by UUID
    /// (stable across reboots; AeroSpace's monitor ordinal isn't) then
    /// by workspaceName. Keys without a colon fall through to a
    /// lexicographic fallback group — they're invalid under v3 but the
    /// renderer stays robust against handcrafted input during debugging.
    static func spacesKeyOrder(_ lhs: String, _ rhs: String) -> Bool {
        spacesSortKey(lhs) < spacesSortKey(rhs)
    }

    static func spacesSortKey(_ key: String) -> (Int, String, String) {
        if let colon = key.firstIndex(of: ":") {
            let uuid = String(key[..<colon])
            let name = String(key[key.index(after: colon)...])
            // Numeric workspaceNames must sort by value, not lexically —
            // otherwise "10" < "2" puts ws10 between ws1 and ws2 and the
            // digit chords get scrambled. Zero-pad to a width comfortably
            // beyond any plausible workspace count.
            let sortName = Int(name).map { String(format: "%09d", $0) } ?? name
            return (0, uuid + "\u{1F}" + sortName, key)
        }
        return (1, key, key)
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
        n.stringValue
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
