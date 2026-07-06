import Foundation
import Testing
@testable import ws_cheatsheet

/// Contract-pinning tests for `CheatsheetDocument`'s wire format. These pin
/// two things at once: (1) a minimal valid document decodes into the shape
/// the renderer expects, and (2) the decoder stays permissive about unknown
/// keys — rune v0.1.0's real output adds a top-level `schemaVersion` and a
/// per-section `source`, and older/newer binaries must keep ignoring both
/// without a schema bump on this side. Fixtures are inline JSON, not
/// committed files, per the frozen-contract rule for this PR.
@Suite("CheatsheetDocument decoding")
struct CheatsheetDataDecodingTests {
    static let minimalValidJSON = """
    {
        "banner": [{ "k": "caps", "v": "Hyper" }],
        "views": [
            {
                "id": "aero",
                "label": "AeroSpace",
                "key": "1",
                "columns": [
                    { "sections": ["windows"] },
                    { "sections": [] },
                    { "sections": [] }
                ]
            }
        ],
        "sections": {
            "windows": {
                "title": "Windows",
                "rows": [["caps + h", "focus left"]],
                "family": "system"
            }
        }
    }
    """

    @Test func minimal_valid_document_round_trips_to_resolved_columns() throws {
        let data = Data(Self.minimalValidJSON.utf8)
        let doc = try JSONDecoder().decode(CheatsheetDocument.self, from: data)

        #expect(doc.banner.count == 1)
        #expect(doc.banner[0].k == "caps")
        #expect(doc.banner[0].v == "Hyper")

        #expect(doc.views.count == 1)
        let lens = doc.views[0]
        #expect(lens.id == "aero")
        #expect(lens.label == "AeroSpace")
        #expect(lens.key == "1")

        // orderedSections flattens the authored columns left-to-right,
        // dropping the empty ones and resolving ids against the pool.
        let ordered = doc.orderedSections(view: lens)
        #expect(ordered.count == 1)
        #expect(ordered[0].title == "Windows")
        #expect(ordered[0].rows == [["caps + h", "focus left"]])
        #expect(ordered[0].family == "system")
    }

    @Test func unknown_top_level_and_per_section_keys_are_ignored() throws {
        // Mirrors rune v0.1.0's real output: a top-level `schemaVersion`
        // and a per-section `source` that no shipped struct declares.
        // Both must decode fine — this is the permissive-decoder contract
        // rune's evolution depends on, and it must not require a parser
        // change to keep working.
        let json = """
        {
            "schemaVersion": "0.1.0",
            "banner": [{ "k": "caps", "v": "Hyper" }],
            "views": [
                {
                    "id": "aero",
                    "label": "AeroSpace",
                    "key": "1",
                    "columns": [{ "sections": ["windows"] }]
                }
            ],
            "sections": {
                "windows": {
                    "title": "Windows",
                    "rows": [["caps + h", "focus left"]],
                    "family": "system",
                    "source": "aerospace.toml"
                }
            }
        }
        """
        let data = Data(json.utf8)
        let doc = try JSONDecoder().decode(CheatsheetDocument.self, from: data)

        #expect(doc.views.count == 1)
        #expect(doc.sections["windows"]?.title == "Windows")
    }
}

@Suite("decodeFailureReason — friendly one-liners")
struct DecodeFailureReasonTests {
    @Test func missing_views_key_names_the_key_and_top_level_location() {
        let json = """
        {
            "banner": [],
            "sections": {}
        }
        """
        let data = Data(json.utf8)
        do {
            _ = try JSONDecoder().decode(CheatsheetDocument.self, from: data)
            Issue.record("expected a decoding error")
        } catch {
            let reason = decodeFailureReason(error)
            #expect(reason.contains("cheatsheet.json"))
            #expect(reason.contains("\"views\""))
            #expect(reason.contains("top level"))
        }
    }

    @Test func type_mismatch_names_the_expected_type_and_path() {
        // "views" is a string instead of an array — a type mismatch nested
        // under the top-level "views" key.
        let json = """
        {
            "banner": [],
            "views": "not-an-array",
            "sections": {}
        }
        """
        let data = Data(json.utf8)
        do {
            _ = try JSONDecoder().decode(CheatsheetDocument.self, from: data)
            Issue.record("expected a decoding error")
        } catch {
            let reason = decodeFailureReason(error)
            #expect(reason.contains("cheatsheet.json"))
            #expect(reason.contains("expected"))
            #expect(reason.contains("views"))
        }
    }

    @Test func non_decoding_error_falls_back_to_its_own_description() {
        struct PlainError: Error, CustomStringConvertible {
            var description: String { "disk on fire" }
        }
        #expect(decodeFailureReason(PlainError()) == "disk on fire")
    }
}

@Suite("Empty-views routing to the error document")
struct EmptyViewsRoutingTests {
    @Test func empty_views_array_decodes_but_is_the_caller_s_cue_to_show_the_error_card() throws {
        // Mirrors main.swift's check: `"views": []` decodes fine (it's
        // valid per the schema) but leaves nothing to render, so the
        // caller — not the decoder — routes this case to `errorDocument`.
        let json = """
        {
            "banner": [],
            "views": [],
            "sections": {}
        }
        """
        let data = Data(json.utf8)
        let doc = try JSONDecoder().decode(CheatsheetDocument.self, from: data)
        #expect(doc.views.isEmpty)
    }

    @Test func error_document_pins_the_error_card_contract() {
        // Pins what the empty-views (and decode-failure) path actually
        // routes to: `errorDocument(reason:)` itself. The decode test above
        // only proves the precondition (`views` can be empty) — deleting
        // main.swift's routing ternary would still leave that test green.
        // Assert the routed-to document's shape directly: a single "error"
        // view whose "error" section carries the reason and a `rune build`
        // fix hint.
        let err = errorDocument(reason: "x")
        #expect(err.views.count == 1)
        #expect(err.views[0].id == "error")
        #expect(err.sections["error"]?.rows.contains(["reason", "x"]) == true)
        #expect(err.sections["error"]?.rows.contains(where: { row in
            row.first == "fix" && row.last?.contains("rune build") == true
        }) == true)
    }
}
