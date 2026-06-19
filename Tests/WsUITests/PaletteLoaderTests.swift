import SwiftUI
import Testing
@testable import WsUI

@Suite("Palette loader — overlay onto Catppuccin fallback")
struct PaletteLoaderTests {
    @Test func empty_map_is_all_catppuccin() {
        let p = Palette.overlay(slots: [:])
        #expect(p.base == Catppuccin.base)
        #expect(p.text == Catppuccin.text)
        #expect(p.blue == Catppuccin.blue)
    }

    @Test func partial_map_replaces_only_named_slots() {
        let p = Palette.overlay(slots: ["base": "#282c34", "text": "#ffffff"])
        #expect(p.base == Color(hex: "#282c34"))
        #expect(p.text == Color(hex: "#ffffff"))
        // Untouched slot still comes from Catppuccin.
        #expect(p.blue == Catppuccin.blue)
        #expect(p.crust == Catppuccin.crust)
    }

    @Test func unparseable_hex_falls_back_for_that_slot() {
        let p = Palette.overlay(slots: ["base": "not-a-hex", "blue": "#81a2be"])
        #expect(p.base == Catppuccin.base)          // bad value → fallback
        #expect(p.blue == Color(hex: "#81a2be"))    // good value → applied
    }

    @Test func malformed_json_yields_empty_slots() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("palette-\(UUID()).json")
        try "{ this is not json".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        setenv("WS_PALETTE", tmp.path, 1)
        defer { unsetenv("WS_PALETTE") }
        #expect(Palette.loadSlots().isEmpty)
    }

    @Test func missing_file_yields_empty_slots() {
        setenv("WS_PALETTE", "/no/such/palette/\(UUID()).json", 1)
        defer { unsetenv("WS_PALETTE") }
        #expect(Palette.loadSlots().isEmpty)
    }

    @Test func valid_file_decodes_slots() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("palette-\(UUID()).json")
        let json = "{\"version\":1,\"source\":\"ghostty\",\"generatedAtNote\":\"x\",\"slots\":{\"base\":\"#282c34\"}}"
        try json.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        setenv("WS_PALETTE", tmp.path, 1)
        defer { unsetenv("WS_PALETTE") }
        #expect(Palette.loadSlots()["base"] == "#282c34")
    }
}
