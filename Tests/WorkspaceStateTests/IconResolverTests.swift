import Testing
import WorkspaceState

@Suite("IconCodepoint encode / decode")
struct IconCodepointTests {

    @Test func decode_roundtrip_bmp() {
        let scalar = IconCodepoint.decode("\\uf0b1")
        #expect(scalar != nil)
        #expect(scalar?.value == 0xF0B1)
        #expect(IconCodepoint.encode(scalar!) == "\\uf0b1")
    }

    @Test func decode_supplementary_pua() {
        let scalar = IconCodepoint.decode("\\u{F0001}")
        #expect(scalar != nil)
        #expect(scalar?.value == 0xF0001)
        #expect(IconCodepoint.isPrivateUseArea(scalar!))
    }

    @Test func decode_malformed_returns_nil() {
        #expect(IconCodepoint.decode("")          == nil)
        #expect(IconCodepoint.decode("f0b1")      == nil)
        #expect(IconCodepoint.decode("\\unotaherx") == nil)
        #expect(IconCodepoint.decode("\\u{}")     == nil)
    }
}

@Suite("IconResolver — surface + override + fallback chain")
struct IconResolverTests {
    func sfExists(_ name: String) -> Bool { name != "missing.symbol" }

    @Test func unavailable_sf_symbol_falls_back() {
        // `sfExists` reports "missing.symbol" unavailable, so the spec's
        // own kind fails direct resolution and the chain continues.
        let spec = IconSpec(
            kind: .sfSymbol,
            symbolName: "missing.symbol",
            fallbackSfSymbol: "play.fill",
            fallbackText: "WK"
        )
        let r = IconResolver.resolve(
            spec: spec,
            targetSurface: .nativeAppKit,
            sfSymbolExists: sfExists(_:)
        )
        #expect(r.kind  == .sfSymbol)
        #expect(r.value == "play.fill")
    }

    @Test func override_wins_when_kind_resolves_on_surface() {
        let spec = IconSpec(
            kind: .sfSymbol,
            symbolName: "star.fill",
            fallbackText: "WK",
            userOverridden: true
        )
        let r = IconResolver.resolve(
            spec: spec,
            targetSurface: .nativeAppKit,
            sfSymbolExists: sfExists(_:)
        )
        #expect(r.kind  == .sfSymbol)
        #expect(r.value == "star.fill")
    }

    @Test func native_prefers_sf_symbol() {
        let spec = IconSpec(
            kind: .sfSymbol,
            symbolName: "play.fill",
            fallbackText: "ST"
        )
        let r = IconResolver.resolve(
            spec: spec,
            targetSurface: .nativeAppKit,
            sfSymbolExists: sfExists(_:)
        )
        #expect(r.kind  == .sfSymbol)
        #expect(r.value == "play.fill")
    }

    @Test func nerd_font_deprecated_falls_back_to_text() {
        // The resolver never emits nerdFont directly (deprecated on these
        // surfaces) — a nerdFont spec resolves through its fallbacks.
        let spec = IconSpec(
            kind: .nerdFont,
            codepoint: "\\uf0b1",
            fontFamily: "JetBrainsMono Nerd Font",
            fallbackText: "WK"
        )
        let r = IconResolver.resolve(
            spec: spec,
            targetSurface: .textBased,
            sfSymbolExists: sfExists(_:)
        )
        #expect(r.kind == .text)
        #expect(r.value == "WK")
    }

    @Test func text_based_surface_uses_fallback_text() {
        // Text-based surface: uses fallbackText when icon unavailable
        let spec = IconSpec(
            kind: .sfSymbol,
            symbolName: "nonexistent.symbol",
            fallbackSfSymbol: "also.nonexistent",
            fallbackText: "ST"
        )
        let r = IconResolver.resolve(
            spec: spec,
            targetSurface: .textBased,
            sfSymbolExists: { _ in false }
        )
        #expect(r.kind  == .text)
        #expect(r.value == "ST")
    }

    @Test func nerd_font_spec_falls_back_to_sf_symbol_on_native() {
        // Native surface: every nerdFont spec skips direct resolution
        // (codepoint validity is irrelevant) → fallback SF symbol wins.
        let spec = IconSpec(
            kind: .nerdFont,
            codepoint: "\\unothex",
            fontFamily: "JetBrainsMono Nerd Font",
            fallbackSfSymbol: "play.fill",
            fallbackText: "ST"
        )
        let r = IconResolver.resolve(
            spec: spec,
            targetSurface: .nativeAppKit,
            sfSymbolExists: sfExists(_:)
        )
        #expect(r.kind  == .sfSymbol)
        #expect(r.value == "play.fill")
    }

    @Test func none_kind_returns_empty() {
        let spec = IconSpec(kind: .none)
        let r = IconResolver.resolve(
            spec: spec,
            targetSurface: .nativeAppKit,
            sfSymbolExists: sfExists(_:)
        )
        #expect(r.kind == .empty)
    }
}
