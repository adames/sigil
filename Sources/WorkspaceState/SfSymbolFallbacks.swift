import Foundation

public enum SfSymbolFallbacks {
    static let table: [String: String] = [
        "stream":  "play.fill",
        "hub":     "square.grid.2x2",
        "grid":    "square.grid.3x3",
        "vault":   "lock.fill",
        "oracle":  "sparkles",
        "sandbox": "cube.box",
        "arena":   "gamecontroller",
        "deck":    "rectangle.stack",
        "shell":   "terminal",
        "daemon":  "cpu",
    ]

    static let defaultSymbol = "circle.fill"

    public static func symbol(forSlotName name: String) -> String {
        table[name.lowercased()] ?? defaultSymbol
    }

    /// Two-letter uppercase abbreviation: first two letters of the name, or
    /// the first letter doubled if the name is single-character.
    public static func textFallback(forSlotName name: String) -> String {
        let upper = name.uppercased()
        if upper.count >= 2 {
            return String(upper.prefix(2))
        }
        if let first = upper.first { return String([first, first]) }
        return "??"
    }
}
