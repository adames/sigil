import Foundation

// MARK: - palette.json schema
//
// The on-disk contract between the resolver (writer) and DesignSystem's
// loader (reader). Slot names match the Catppuccin token names 1:1 so the
// loader can overlay any subset onto its compiled-in fallback. There is
// deliberately NO wall-clock timestamp — it would churn diffs and break
// the codebase's no-nondeterminism rule; `source` is provenance enough.

public struct PaletteDocument: Codable, Equatable {
    public var version: Int
    public var source: String
    public var generatedAtNote: String
    public var slots: [String: String]

    public init(version: Int = 1, source: String, generatedAtNote: String, slots: [String: String]) {
        self.version = version
        self.source = source
        self.generatedAtNote = generatedAtNote
        self.slots = slots
    }
}

// MARK: - Resolver

public enum PaletteResolver {
    /// Minimum foreground/background WCAG contrast for a terminal palette
    /// to be considered usable. Below this we'd derive an unreadable gray
    /// ramp, so the resolver bails and the loader keeps Catppuccin.
    public static let minContrast = 4.5

    /// The background→foreground mix fractions defining Sigil's gray ramp.
    /// Negative fractions darken *below* the background. Ordered darkest
    /// surface → brightest text. Tuned to read well on both Catppuccin
    /// Mocha and Ghostty's default theme.
    static let ramp: [(slot: String, t: Double)] = [
        ("crust", -0.06),
        ("mantle", -0.03),
        ("base", 0.00),
        ("surface0", 0.10),
        ("surface1", 0.16),
        ("surface2", 0.22),
        ("overlay0", 0.34),
        ("overlay1", 0.45),
        ("overlay2", 0.55),
        ("subtext0", 0.72),
        ("subtext1", 0.86),
        ("text", 1.00),
    ]

    public enum Failure: Error, Equatable {
        case missingSurfaces   // no background or foreground in the source
        case lowContrast(Double)
    }

    /// Derive a full Sigil palette from a parsed terminal palette.
    /// Throws `Failure` when the source is too thin or too low-contrast to
    /// derive a readable ramp — the caller should then leave Sigil on its
    /// Catppuccin fallback rather than write a broken palette.json.
    public static func resolve(
        from g: GhosttyPalette,
        source: String = "ghostty"
    ) throws -> PaletteDocument {
        guard let bg = g.background, let fg = g.foreground else {
            throw Failure.missingSurfaces
        }

        let contrast = ColorMath.contrastRatio(bg, fg)
        guard contrast >= minContrast else {
            throw Failure.lowContrast(contrast)
        }

        var slots: [String: String] = [:]

        // Gray ramp: interpolate background → foreground.
        for entry in ramp {
            slots[entry.slot] = ColorMath.mix(bg, fg, entry.t).hex
        }

        // Accents: map ANSI normals to the primary tokens and the bright
        // variants to their siblings. When a bright is missing, fabricate
        // it by lightening the normal; when a normal is missing, darken
        // the bright. (§12.3 derive-sibling policy.)
        func normal(_ i: Int) -> RGB? { g.ansi[i] }
        func bright(_ i: Int) -> RGB? { g.ansi[i + 8] }

        // primary token ← normal (fallback: darken its bright sibling)
        func primary(_ i: Int) -> RGB? {
            normal(i) ?? bright(i).map { ColorMath.adjustLightness($0, by: -0.10) }
        }
        // sibling token ← bright (fallback: lighten its normal sibling)
        func sibling(_ i: Int) -> RGB? {
            bright(i) ?? normal(i).map { ColorMath.adjustLightness($0, by: 0.10) }
        }

        func put(_ name: String, _ rgb: RGB?) {
            if let rgb { slots[name] = rgb.hex }
        }

        // ANSI 1 red, 2 green, 3 yellow, 4 blue, 5 magenta, 6 cyan.
        put("red", primary(1))
        put("maroon", sibling(1))            // bright red
        put("green", primary(2))
        put("yellow", primary(3))
        put("peach", sibling(3))             // bright yellow → warm sibling
        put("blue", primary(4))
        put("sapphire", sibling(4))          // bright blue
        put("mauve", primary(5))
        put("pink", sibling(5))              // bright magenta
        put("teal", primary(6))
        put("sky", sibling(6))               // bright cyan

        // Pastels Sigil needs that ANSI doesn't name: lighten a base hue.
        if let blue = primary(4) {
            put("lavender", ColorMath.adjustLightness(blue, by: 0.12))
        }
        if let red = primary(1) {
            put("rosewater", ColorMath.adjustLightness(red, by: 0.16))
            put("flamingo", ColorMath.adjustLightness(red, by: 0.10))
        }

        return PaletteDocument(
            version: 1,
            source: source,
            generatedAtNote: "written by `ws palette sync`",
            slots: slots
        )
    }
}
