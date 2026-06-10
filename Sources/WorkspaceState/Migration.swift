import Foundation

public enum MigrationError: Error, Equatable, CustomStringConvertible {
    case malformedJSON
    case missingSpaces
    case missingVersion
    case unsupportedVersion(Int)

    public var description: String {
        switch self {
        case .malformedJSON:           return "spaces.json is not valid JSON"
        case .missingSpaces:           return "spaces.json has no `spaces` object"
        case .missingVersion:          return "spaces.json has no integer `version` field (expected \(Migration.currentVersion))"
        case .unsupportedVersion(let v): return "unsupported spaces.json version: \(v) (only v\(Migration.currentVersion) is accepted)"
        }
    }
}

public struct MigrationResult {
    /// The validated, canonically-rendered spaces.json output. Re-rendering
    /// produces a jq-friendly deterministic key order without semantic changes.
    public let outputJSON: String

    public init(outputJSON: String) {
        self.outputJSON = outputJSON
    }
}

/// spaces.json v3 validator + canonical pretty-printer.
/// Rejects anything that isn't v3; the transformation paths for v1/v2 were retired.
public enum Migration {
    public static let currentVersion = 3

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

        // A missing (or non-integer) `version` is its own diagnostic —
        // defaulting it to 1 used to send users debugging a "v1 file"
        // that never claimed to be one.
        guard let version = raw["version"] as? Int else {
            throw MigrationError.missingVersion
        }
        guard version == currentVersion else {
            throw MigrationError.unsupportedVersion(version)
        }
        guard raw["spaces"] is [String: Any] else {
            throw MigrationError.missingSpaces
        }

        return MigrationResult(outputJSON: render(root: raw))
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
        if let n = value as? NSNumber {
            // Type-check CFBoolean rather than `as? Bool`: bridging casts
            // an integer NSNumber holding 0/1 to Bool successfully, which
            // would silently rewrite `"count": 1` as `"count": true`.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return n.boolValue ? "true" : "false"
            }
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
