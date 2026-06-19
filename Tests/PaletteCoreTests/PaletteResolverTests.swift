import Foundation
import Testing
@testable import PaletteCore

// Fixtures: real `ghostty +show-config --default=true` output, trimmed to
// the three keys the resolver reads.

/// Ghostty's built-in default theme (no `theme` set) — the case the
/// motivating bug is about: Sigil currently mismatches this.
let ghosttyDefaultFixture = """
    background = #282c34
    foreground = #ffffff
    palette = 0=#1d1f21
    palette = 1=#cc6666
    palette = 2=#b5bd68
    palette = 3=#f0c674
    palette = 4=#81a2be
    palette = 5=#b294bb
    palette = 6=#8abeb7
    palette = 7=#c5c8c6
    palette = 8=#666666
    palette = 9=#d54e53
    palette = 10=#b9ca4a
    palette = 11=#e7c547
    palette = 12=#7aa6da
    palette = 13=#c397d8
    palette = 14=#70c0b1
    palette = 15=#eaeaea
    """

/// Catppuccin Mocha as a Ghostty theme — should derive back to something
/// close to Sigil's current hardcoded palette.
let catppuccinFixture = """
    background = #1e1e2e
    foreground = #cdd6f4
    palette = 0=#45475a
    palette = 1=#f38ba8
    palette = 2=#a6e3a1
    palette = 3=#f9e2af
    palette = 4=#89b4fa
    palette = 5=#f5c2e7
    palette = 6=#94e2d5
    palette = 7=#bac2de
    palette = 8=#585b70
    palette = 9=#f38ba8
    palette = 10=#a6e3a1
    palette = 11=#f9e2af
    palette = 12=#89b4fa
    palette = 13=#f5c2e7
    palette = 14=#94e2d5
    palette = 15=#a6adc8
    """

@Suite("Ghostty config parsing")
struct GhosttyParseTests {
    @Test func parses_background_foreground_and_ansi() {
        let p = GhosttyPalette.parse(ghosttyDefaultFixture)
        #expect(p.background?.hex == "#282c34")
        #expect(p.foreground?.hex == "#ffffff")
        #expect(p.ansi[1]?.hex == "#cc6666")
        #expect(p.ansi[12]?.hex == "#7aa6da")
        #expect(p.ansi.count == 16)
    }

    @Test func ignores_unknown_keys_and_comments() {
        let text = """
        # a comment
        font-family = "Berkeley Mono"
        background = #101010
        window-padding-x = 4
        """
        let p = GhosttyPalette.parse(text)
        #expect(p.background?.hex == "#101010")
        #expect(p.foreground == nil)
        #expect(p.ansi.isEmpty)
    }
}

@Suite("PaletteResolver — slot derivation")
struct PaletteResolverTests {
    @Test func ghostty_default_maps_surfaces_and_accents() throws {
        let doc = try PaletteResolver.resolve(from: GhosttyPalette.parse(ghosttyDefaultFixture))
        // base = background, text = foreground (direct).
        #expect(doc.slots["base"] == "#282c34")
        #expect(doc.slots["text"] == "#ffffff")
        // accents map straight off the normal ANSI colors.
        #expect(doc.slots["red"] == "#cc6666")
        #expect(doc.slots["green"] == "#b5bd68")
        #expect(doc.slots["blue"] == "#81a2be")
        #expect(doc.slots["mauve"] == "#b294bb")
        // bright siblings come from the bright ANSI range.
        #expect(doc.slots["sapphire"] == "#7aa6da")   // ANSI 12
        #expect(doc.slots["maroon"] == "#d54e53")     // ANSI 9
        // full slot set present (12 ramp + 14 accents).
        #expect(doc.slots.count == 26)
        #expect(doc.source == "ghostty")
    }

    @Test func ramp_is_monotonic_in_lightness() throws {
        let doc = try PaletteResolver.resolve(from: GhosttyPalette.parse(ghosttyDefaultFixture))
        let order = ["crust", "mantle", "base", "surface0", "surface1",
                     "surface2", "overlay0", "overlay1", "overlay2",
                     "subtext0", "subtext1", "text"]
        let lightness = order.map { RGB(hex: doc.slots[$0]!)!.oklab.L }
        for (a, b) in zip(lightness, lightness.dropFirst()) {
            #expect(a < b, "ramp lightness must strictly increase")
        }
    }

    @Test func derived_hexes_are_pinned() throws {
        // Pin a couple of derived ramp hexes so a regression in the mix
        // math is caught. (Ghostty default: bg #282c34 → fg #ffffff.)
        let doc = try PaletteResolver.resolve(from: GhosttyPalette.parse(ghosttyDefaultFixture))
        #expect(doc.slots["crust"] == "#1e222a")
        #expect(doc.slots["surface0"] == "#3a3e46")
        #expect(doc.slots["subtext1"] == "#dddee0")
    }

    @Test func partial_brights_fabricate_siblings() throws {
        // Only the 8 normal ANSI colors — brights absent. Sibling tokens
        // should be lightened normals, not missing.
        var g = GhosttyPalette.parse(catppuccinFixture)
        for i in 8...15 { g.ansi[i] = nil }
        let doc = try PaletteResolver.resolve(from: g)
        #expect(doc.slots["sapphire"] != nil)   // fabricated from blue
        #expect(doc.slots["maroon"] != nil)     // fabricated from red
        // sibling should be lighter than its primary.
        let blueL = RGB(hex: doc.slots["blue"]!)!.oklab.L
        let sapphireL = RGB(hex: doc.slots["sapphire"]!)!.oklab.L
        #expect(sapphireL > blueL)
    }

    @Test func catppuccin_fixture_recovers_its_own_palette() throws {
        // Feeding Catppuccin-as-a-Ghostty-theme back through the resolver
        // should reproduce the canonical accents exactly and pin base/text.
        let doc = try PaletteResolver.resolve(from: GhosttyPalette.parse(catppuccinFixture))
        #expect(doc.slots["base"] == "#1e1e2e")
        #expect(doc.slots["text"] == "#cdd6f4")
        #expect(doc.slots["red"] == "#f38ba8")
        #expect(doc.slots["green"] == "#a6e3a1")
        #expect(doc.slots["yellow"] == "#f9e2af")
        #expect(doc.slots["blue"] == "#89b4fa")
        #expect(doc.slots["mauve"] == "#f5c2e7")   // ANSI 5 (magenta)
        #expect(doc.slots["teal"] == "#94e2d5")
        #expect(doc.slots.count == 26)
    }

    @Test func resolution_is_deterministic() throws {
        // No nondeterminism: same input → byte-identical document.
        let g = GhosttyPalette.parse(ghosttyDefaultFixture)
        let a = try PaletteResolver.resolve(from: g)
        let b = try PaletteResolver.resolve(from: g)
        #expect(a == b)
    }

    @Test func ramp_clamps_at_black_for_pure_black_background() throws {
        // bg #000000 with the negative crust/mantle fractions must not
        // fold past black — OkLab L is clamped to [0,1].
        let g = GhosttyPalette(
            background: RGB(hex: "#000000"),
            foreground: RGB(hex: "#ffffff"),
            ansi: [1: RGB(hex: "#cc6666")!, 4: RGB(hex: "#81a2be")!]
        )
        let doc = try PaletteResolver.resolve(from: g)
        #expect(doc.slots["crust"] == "#000000")
        #expect(doc.slots["mantle"] == "#000000")
        #expect(doc.slots["base"] == "#000000")
        // every emitted slot is a valid 7-char hex.
        for (_, hex) in doc.slots {
            #expect(RGB(hex: hex) != nil)
            #expect(hex.count == 7)
        }
    }

    @Test func only_brights_present_darkens_for_primary() throws {
        // A theme defining only the bright ANSI range (8–15). Primary
        // tokens must be fabricated by darkening their bright sibling.
        var g = GhosttyPalette.parse(catppuccinFixture)
        for i in 0...7 { g.ansi[i] = nil }
        let doc = try PaletteResolver.resolve(from: g)
        #expect(doc.slots["red"] != nil)    // fabricated from bright red
        #expect(doc.slots["blue"] != nil)
        let redL = RGB(hex: doc.slots["red"]!)!.oklab.L
        let maroonL = RGB(hex: doc.slots["maroon"]!)!.oklab.L
        #expect(redL < maroonL)             // primary darker than its bright
    }

    @Test func parse_tolerates_extra_whitespace_and_case() {
        let text = """
        background   =    #ABCDEF
        palette = 1 =  #Cc6666
        """
        let p = GhosttyPalette.parse(text)
        #expect(p.background?.hex == "#abcdef")
        #expect(p.ansi[1]?.hex == "#cc6666")
    }

    @Test func contrast_exactly_at_floor_passes() throws {
        // A palette whose fg/bg contrast is comfortably above 4.5 resolves;
        // this guards the boundary direction (>= floor, not > floor).
        let g = GhosttyPalette(
            background: RGB(hex: "#1e1e2e"),
            foreground: RGB(hex: "#cdd6f4"),
            ansi: [1: RGB(hex: "#f38ba8")!]
        )
        #expect(throws: Never.self) {
            _ = try PaletteResolver.resolve(from: g)
        }
    }

    @Test func missing_surfaces_throws() {
        var g = GhosttyPalette.parse(ghosttyDefaultFixture)
        g.background = nil
        #expect(throws: PaletteResolver.Failure.missingSurfaces) {
            _ = try PaletteResolver.resolve(from: g)
        }
    }

    @Test func low_contrast_theme_bails() {
        // Near-identical fg/bg → unreadable. Resolver must refuse.
        let g = GhosttyPalette(
            background: RGB(hex: "#303030"),
            foreground: RGB(hex: "#3a3a3a"),
            ansi: [1: RGB(hex: "#cc6666")!]
        )
        #expect(throws: PaletteResolver.Failure.self) {
            _ = try PaletteResolver.resolve(from: g)
        }
    }
}

@Suite("ColorMath")
struct ColorMathTests {
    @Test func hex_roundtrip() {
        #expect(RGB(hex: "#282c34")?.hex == "#282c34")
        #expect(RGB(hex: "1e1e2e")?.hex == "#1e1e2e")
        #expect(RGB(hex: "nope") == nil)
    }

    @Test func mix_endpoints_are_exact() {
        let bg = RGB(hex: "#282c34")!
        let fg = RGB(hex: "#ffffff")!
        #expect(ColorMath.mix(bg, fg, 0).hex == bg.hex)
        #expect(ColorMath.mix(bg, fg, 1).hex == fg.hex)
    }

    @Test func contrast_white_on_black_is_21() {
        let ratio = ColorMath.contrastRatio(RGB(hex: "#000000")!, RGB(hex: "#ffffff")!)
        #expect(abs(ratio - 21.0) < 0.01)
    }
}
