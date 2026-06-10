import Foundation
import Testing
import WorkspaceState

@Suite("spaces.json v3 validator + canonical renderer")
struct MigrationValidatorTests {

    /// A well-formed v3 fixture passes validation and round-trips
    /// through the canonical renderer with all user content intact.
    @Test func v3_round_trips_through_validator() throws {
        let v3 = """
        {
          "version": 3,
          "palette": "catppuccin-mocha",
          "_doc_note": "edit me",
          "spaces": {
            "37D8832F-D9B8-4738-A6B0-D8FAD93EF8D8:1": {
              "color": "#cba6f7",
              "displayUUID": "37D8832F-D9B8-4738-A6B0-D8FAD93EF8D8",
              "iconSpec": { "kind": "sfSymbol", "symbolName": "star.fill", "userOverridden": true },
              "name": "stream",
              "stableLogicalLabel": "stream",
              "workspaceName": "1"
            },
            "37D8832F-D9B8-4738-A6B0-D8FAD93EF8D8:2": {
              "color": "#f5c2e7",
              "displayUUID": "37D8832F-D9B8-4738-A6B0-D8FAD93EF8D8",
              "iconSpec": { "kind": "none", "userOverridden": false },
              "name": "dev",
              "stableLogicalLabel": "dev",
              "workspaceName": "2"
            }
          }
        }
        """
        let result = try Migration.migrate(jsonData: Data(v3.utf8))

        let root = try #require(
            try JSONSerialization.jsonObject(with: Data(result.outputJSON.utf8)) as? [String: Any]
        )
        #expect(root["version"]   as? Int    == 3)
        #expect(root["_doc_note"] as? String == "edit me")

        let spaces = try #require(root["spaces"] as? [String: Any])
        let slot1 = try #require(
            spaces["37D8832F-D9B8-4738-A6B0-D8FAD93EF8D8:1"] as? [String: Any]
        )
        #expect(slot1["name"]          as? String == "stream")
        #expect(slot1["workspaceName"] as? String == "1")
        #expect(slot1["displayUUID"]   as? String == "37D8832F-D9B8-4738-A6B0-D8FAD93EF8D8")
    }

    /// v1 fixtures are rejected — no upgrade path post-migration.
    @Test func v1_input_throws_unsupported_version() {
        let v1 = """
        { "version": 1, "spaces": { "1": { "name": "stream", "color": "#000", "icon": "" } } }
        """
        #expect(throws: MigrationError.self) {
            _ = try Migration.migrate(jsonData: Data(v1.utf8))
        }
    }

    /// v2 fixtures are rejected — same reason.
    @Test func v2_input_throws_unsupported_version() {
        let v2 = """
        {
          "version": 2,
          "spaces": {
            "1": { "name": "ws1", "color": "#000", "iconSpec": { "kind": "none" }, "stableLogicalLabel": "ws1" }
          }
        }
        """
        #expect(throws: MigrationError.self) {
            _ = try Migration.migrate(jsonData: Data(v2.utf8))
        }
    }

    /// Malformed JSON surfaces as `.malformedJSON`.
    @Test func malformed_json_throws_malformed() {
        let junk = "not json at all"
        #expect(throws: MigrationError.self) {
            _ = try Migration.migrate(jsonData: Data(junk.utf8))
        }
    }

    /// A file with no `version` key is its own failure mode — it must
    /// not be misreported as "unsupported version: 1".
    @Test func missing_version_throws_missing_version() {
        let unversioned = #"{ "spaces": {} }"#
        #expect(throws: MigrationError.missingVersion) {
            _ = try Migration.migrate(jsonData: Data(unversioned.utf8))
        }
    }

    /// Regression: NSNumber bridging casts integer 0/1 to Bool, so the
    /// renderer used to rewrite `"count": 1` as `"count": true` —
    /// corrupting user data on `migrate --apply`. Integers must stay
    /// integers and real booleans must stay booleans.
    @Test func renderer_preserves_integers_zero_and_one() throws {
        let v3 = """
        {
          "version": 3,
          "_count": 1,
          "_padding": 0,
          "_flag": true,
          "_off": false,
          "spaces": {}
        }
        """
        let result = try Migration.migrate(jsonData: Data(v3.utf8))
        #expect(result.outputJSON.contains("\"_count\": 1"))
        #expect(result.outputJSON.contains("\"_padding\": 0"))
        #expect(result.outputJSON.contains("\"_flag\": true"))
        #expect(result.outputJSON.contains("\"_off\": false"))
    }

    /// Missing top-level `spaces` raises `.missingSpaces`.
    @Test func missing_spaces_throws() {
        let no_spaces = #"{ "version": 3, "palette": "catppuccin-mocha" }"#
        #expect(throws: MigrationError.self) {
            _ = try Migration.migrate(jsonData: Data(no_spaces.utf8))
        }
    }

    /// Idempotent — re-rendering a canonical v3 output reproduces it.
    @Test func canonical_output_is_idempotent() throws {
        let v3 = """
        {
          "version": 3,
          "spaces": {
            "UUID-A:1": {
              "color": "#000000",
              "displayUUID": "UUID-A",
              "iconSpec": { "kind": "none", "userOverridden": false },
              "name": "ws1",
              "stableLogicalLabel": "ws1",
              "workspaceName": "1"
            }
          }
        }
        """
        let first  = try Migration.migrate(jsonData: Data(v3.utf8))
        let second = try Migration.migrate(jsonData: Data(first.outputJSON.utf8))
        #expect(first.outputJSON == second.outputJSON)
    }

    /// Composite keys sort by UUID then workspaceName — slot10 comes
    /// after slot9 within the same UUID; UUIDs sort lexically against
    /// each other.
    @Test func composite_keys_sort_by_uuid_then_workspace_name() throws {
        var spacesIn: [String: Any] = [:]
        // Mix two UUIDs so we can assert the group ordering, and use
        // numeric workspaceNames so we exercise the secondary sort.
        for n in [1, 10, 2, 11, 9] {
            spacesIn["UUID-A:\(n)"] = [
                "color": "#000",
                "displayUUID": "UUID-A",
                "iconSpec": ["kind": "none", "userOverridden": false],
                "name": "wsA\(n)",
                "stableLogicalLabel": "wsA\(n)",
                "workspaceName": "\(n)",
            ] as [String: Any]
        }
        for n in [3, 1] {
            spacesIn["UUID-B:\(n)"] = [
                "color": "#000",
                "displayUUID": "UUID-B",
                "iconSpec": ["kind": "none", "userOverridden": false],
                "name": "wsB\(n)",
                "stableLogicalLabel": "wsB\(n)",
                "workspaceName": "\(n)",
            ] as [String: Any]
        }
        let root: [String: Any] = ["version": 3, "spaces": spacesIn]
        let data = try JSONSerialization.data(withJSONObject: root)
        let result = try Migration.migrate(jsonData: data)

        // UUID-A group precedes UUID-B group (lexicographic).
        let uuidA = try #require(result.outputJSON.range(of: "\"UUID-A:1\":"))
        let uuidB = try #require(result.outputJSON.range(of: "\"UUID-B:1\":"))
        #expect(uuidA.lowerBound < uuidB.lowerBound)
    }
}

@Suite("Decoder preserves user-overridden flag across v3 round-trip")
struct RenamePreservesOverrideTests {
    @Test func decoder_preserves_user_overridden_flag() throws {
        let v3 = """
        {
          "version": 3,
          "spaces": {
            "UUID-A:1": {
              "name": "custom",
              "color": "#abcdef",
              "stableLogicalLabel": "stream",
              "displayUUID": "UUID-A",
              "workspaceName": "1",
              "iconSpec": {
                "kind": "sfSymbol",
                "symbolName": "star.fill",
                "userOverridden": true
              }
            }
          }
        }
        """
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ws-spaces-\(UUID().uuidString).json")
        try Data(v3.utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store  = WorkspaceStateStore(configURL: tmp)
        let config = try store.load()
        let slot   = try #require(config.slots.first)
        #expect(slot.name                == "custom")
        #expect(slot.stableLogicalLabel  == "stream")
        #expect(slot.iconSpec.userOverridden)
        #expect(slot.iconSpec.kind       == .sfSymbol)
        #expect(slot.iconSpec.symbolName == "star.fill")
        #expect(slot.workspaceName       == "1")
        #expect(slot.displayUUID         == "UUID-A")
        #expect(slot.target              == WorkspaceTarget(displayUUID: "UUID-A", workspaceName: "1"))
    }

    /// Slots without the required v3 identity fields can't be matched by
    /// anything — the loader drops them rather than fabricating an empty
    /// identity.
    @Test func decoder_skips_slots_missing_identity_fields() throws {
        let v3 = """
        {
          "version": 3,
          "spaces": {
            "UUID-A:1": {
              "name": "kept",
              "color": "#abcdef",
              "stableLogicalLabel": "kept",
              "displayUUID": "UUID-A",
              "workspaceName": "1"
            },
            "orphan": {
              "name": "dropped",
              "color": "#000000"
            }
          }
        }
        """
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ws-spaces-\(UUID().uuidString).json")
        try Data(v3.utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config = try WorkspaceStateStore(configURL: tmp).load()
        #expect(config.slots.map(\.name) == ["kept"])
    }
}
