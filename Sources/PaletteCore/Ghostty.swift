import Foundation

// MARK: - Ghostty config parsing
//
// `ghostty +show-config --default=true` emits the fully-resolved palette
// as flat `key = value` lines, e.g.
//
//     background = #282c34
//     foreground = #ffffff
//     palette = 0=#1d1f21
//     palette = 1=#cc6666
//     ...
//
// We only care about three keys. Everything else is ignored, so this
// parser is robust to Ghostty growing new config keys.

/// The colors a terminal hands us: two surfaces and up to 16 ANSI slots.
/// Any field may be absent (a hand-rolled config that only sets a few
/// keys) — the resolver fills gaps from siblings or bails to the floor.
public struct GhosttyPalette: Equatable {
    public var background: RGB?
    public var foreground: RGB?
    /// ANSI index (0…15) → color. Sparse: only the indices the config set.
    public var ansi: [Int: RGB]

    public init(background: RGB? = nil, foreground: RGB? = nil, ansi: [Int: RGB] = [:]) {
        self.background = background
        self.foreground = foreground
        self.ansi = ansi
    }

    /// Parse the textual output of `ghostty +show-config`.
    public static func parse(_ text: String) -> GhosttyPalette {
        var result = GhosttyPalette()
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)

            switch key {
            case "background":
                result.background = RGB(hex: value)
            case "foreground":
                result.foreground = RGB(hex: value)
            case "palette":
                // value is "N=#rrggbb"
                guard let inner = value.firstIndex(of: "=") else { continue }
                let idxStr = value[..<inner].trimmingCharacters(in: .whitespaces)
                let hex = value[value.index(after: inner)...].trimmingCharacters(in: .whitespaces)
                if let idx = Int(idxStr), let rgb = RGB(hex: hex) {
                    result.ansi[idx] = rgb
                }
            default:
                continue
            }
        }
        return result
    }
}
