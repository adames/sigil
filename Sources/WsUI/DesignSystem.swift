import Foundation
import PaletteCore
import SwiftUI

// MARK: - Catppuccin Mocha palette
//
// Complete Catppuccin Mocha tokens, ordered as they're laid out in the
// upstream palette: backgrounds → surfaces → overlays → text → accents.
// Shared across every sigil overlay so the cheatsheet, prompts, and
// picker read as one surface.
//
// Caseless struct (vs enum) follows the Swift convention for "namespace
// for constants" — `enum` is conventionally for tagged unions.

public struct Catppuccin {
    // Backgrounds (darkest → lightest base layer)
    public static let crust    = Color(hex: "#11111b") ?? .black
    public static let mantle   = Color(hex: "#181825") ?? .black
    public static let base     = Color(hex: "#1e1e2e") ?? .black

    // Elevated surfaces (cards, fills)
    public static let surface0 = Color(hex: "#313244") ?? .gray
    public static let surface1 = Color(hex: "#45475a") ?? .gray
    public static let surface2 = Color(hex: "#585b70") ?? .gray

    // Overlays (borders, dividers, low-emphasis text)
    public static let overlay0 = Color(hex: "#6c7086") ?? .gray
    public static let overlay1 = Color(hex: "#7f849c") ?? .gray
    public static let overlay2 = Color(hex: "#9399b2") ?? .gray

    // Text (foreground hierarchy)
    public static let subtext0 = Color(hex: "#a6adc8") ?? .white
    public static let subtext1 = Color(hex: "#bac2de") ?? .white
    public static let text     = Color(hex: "#cdd6f4") ?? .white

    // Accents
    public static let rosewater = Color(hex: "#f5e0dc") ?? .white
    public static let flamingo  = Color(hex: "#f2cdcd") ?? .pink
    public static let pink      = Color(hex: "#f5c2e7") ?? .pink
    public static let mauve     = Color(hex: "#cba6f7") ?? .purple
    public static let red       = Color(hex: "#f38ba8") ?? .red
    public static let maroon    = Color(hex: "#eba0ac") ?? .pink
    public static let peach     = Color(hex: "#fab387") ?? .orange
    public static let yellow    = Color(hex: "#f9e2af") ?? .yellow
    public static let green     = Color(hex: "#a6e3a1") ?? .green
    public static let teal      = Color(hex: "#94e2d5") ?? .teal
    public static let sky       = Color(hex: "#89dceb") ?? .cyan
    public static let sapphire  = Color(hex: "#74c7ec") ?? .blue
    public static let blue      = Color(hex: "#89b4fa") ?? .blue
    public static let lavender  = Color(hex: "#b4befe") ?? .indigo

    private init() {}
}

// MARK: - Resolved palette
//
// The surface every overlay actually paints from. At first access it
// reads ~/.config/workspace/palette.json (written by `ws palette sync`,
// derived from the user's terminal) and overlays whatever slots it finds
// onto the Catppuccin fallback. Missing file, malformed JSON, or an
// absent slot all fall through to Catppuccin — so Sigil always renders,
// and with nothing configured it looks exactly like it did before.

public struct Palette {
    public let crust, mantle, base: Color
    public let surface0, surface1, surface2: Color
    public let overlay0, overlay1, overlay2: Color
    public let subtext0, subtext1, text: Color
    public let rosewater, flamingo, pink, mauve, red, maroon, peach: Color
    public let yellow, green, teal, sky, sapphire, blue, lavender: Color

    /// Loaded once per process at first access. `static let` is lazy and
    /// thread-safe, so the JSON read happens exactly once.
    public static let resolved: Palette = load()

    /// Resolve `palette.json`'s location. `WS_PALETTE` overrides for tests
    /// and unusual layouts; otherwise it sits beside spaces.json under
    /// the workspace config dir.
    static var paletteURL: URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["WS_PALETTE"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/workspace/palette.json")
    }

    /// Read + decode the palette file, returning the raw slot→hex map.
    /// Any failure (no file, bad JSON) yields an empty map → all
    /// Catppuccin.
    static func loadSlots() -> [String: String] {
        guard let data = try? Data(contentsOf: paletteURL),
              let doc = try? JSONDecoder().decode(PaletteDocument.self, from: data)
        else { return [:] }
        return doc.slots
    }

    static func load() -> Palette {
        overlay(slots: loadSlots())
    }

    /// Overlay a slot→hex map onto the Catppuccin fallback. Pure (no I/O)
    /// so the fallback semantics are unit-testable: an empty map → all
    /// Catppuccin; a partial map → only those slots replaced; an
    /// unparseable hex for a slot → that slot stays Catppuccin.
    static func overlay(slots: [String: String]) -> Palette {
        // Each slot: parse the JSON hex if present and valid, else the
        // compiled-in Catppuccin constant.
        func c(_ name: String, _ fallback: Color) -> Color {
            if let hex = slots[name], let parsed = Color(hex: hex) { return parsed }
            return fallback
        }
        return Palette(
            crust: c("crust", Catppuccin.crust),
            mantle: c("mantle", Catppuccin.mantle),
            base: c("base", Catppuccin.base),
            surface0: c("surface0", Catppuccin.surface0),
            surface1: c("surface1", Catppuccin.surface1),
            surface2: c("surface2", Catppuccin.surface2),
            overlay0: c("overlay0", Catppuccin.overlay0),
            overlay1: c("overlay1", Catppuccin.overlay1),
            overlay2: c("overlay2", Catppuccin.overlay2),
            subtext0: c("subtext0", Catppuccin.subtext0),
            subtext1: c("subtext1", Catppuccin.subtext1),
            text: c("text", Catppuccin.text),
            rosewater: c("rosewater", Catppuccin.rosewater),
            flamingo: c("flamingo", Catppuccin.flamingo),
            pink: c("pink", Catppuccin.pink),
            mauve: c("mauve", Catppuccin.mauve),
            red: c("red", Catppuccin.red),
            maroon: c("maroon", Catppuccin.maroon),
            peach: c("peach", Catppuccin.peach),
            yellow: c("yellow", Catppuccin.yellow),
            green: c("green", Catppuccin.green),
            teal: c("teal", Catppuccin.teal),
            sky: c("sky", Catppuccin.sky),
            sapphire: c("sapphire", Catppuccin.sapphire),
            blue: c("blue", Catppuccin.blue),
            lavender: c("lavender", Catppuccin.lavender)
        )
    }
}

// MARK: - Shape + typography tokens

public struct PromptStyle {
    public static let pillCorner: CGFloat = 6
    public static let pillHeight: CGFloat = 22
    public static let cardCorner: CGFloat = 10

    /// Distance from the top of the screen to the top of the overlay
    /// card. Matches Raycast's search-box top so the two surfaces feel
    /// like part of the same launcher family.
    public static let topInset: CGFloat = 120

    private init() {}
}

// MARK: - Comparable.clamped

public extension Comparable {
    /// Clamp `self` to a closed range. Used in overlay pickers where the
    /// SwiftUI selection index can briefly outlive the filtered list during
    /// a refilter.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
