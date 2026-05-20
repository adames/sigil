import Foundation
import Testing
import WorkspaceState

@Suite("v1 → v2 → v3 spaces.json migration chain")
struct MigrationChainTests {

    /// v1 fixture chains all the way to v3 in a single migrate() call.
    /// v3 key shape is `_unassigned:slot<N>` for v2-era slots that haven't
    /// been reconciled against a live aerospace monitor yet.
    @Test func v1_to_v3_chains_both_steps() throws {
        let v1 = """
        {
          "version": 1,
          "palette": "catppuccin-mocha",
          "_doc_note": "edit me",
          "spaces": {
            "1": { "name": "stream", "color": "#cba6f7", "icon": "\u{F0A0}" },
            "2": { "name": "hub",    "color": "#f5c2e7", "icon": "" }
          }
        }
        """
        let result = try Migration.migrate(jsonData: Data(v1.utf8))
        #expect(!result.alreadyV2)
        #expect(result.slotsTouched > 0)
        #expect(result.unassignedSlots == 2)

        let outData = Data(result.outputJSON.utf8)
        let root = try #require(
            try JSONSerialization.jsonObject(with: outData) as? [String: Any]
        )
        #expect(root["version"]   as? Int    == 3)
        #expect(root["_doc_note"] as? String == "edit me")

        let spaces = try #require(root["spaces"] as? [String: Any])
        let slot1 = try #require(
            spaces["_unassigned:slot1"] as? [String: Any],
            "v3 composite key should replace integer-string key"
        )
        #expect(slot1["name"]                as? String == "stream")
        #expect(slot1["color"]               as? String == "#cba6f7")
        #expect(slot1["stableLogicalLabel"]  as? String == "stream")
        #expect(slot1["displayUUID"]         as? String == "_unassigned")
        #expect(slot1["workspaceName"]       as? String == "slot1")
        #expect(slot1["icon"] == nil, "legacy icon field should be removed")

        let spec = slot1["iconSpec"] as? [String: Any] ?? [:]
        #expect(spec["kind"]           as? String == "nerdFont")
        #expect(spec["codepoint"]      as? String == "\\uf0a0")
        #expect(spec["fontFamily"]     as? String == "JetBrainsMono Nerd Font")
        #expect(spec["userOverridden"] as? Bool   == false)
    }

    /// Empty icon string → kind=none, fallbacks attached for downstream use.
    @Test func empty_icon_yields_kind_none() throws {
        let v1 = """
        { "version": 1, "spaces": { "1": { "name": "stream", "color": "#000000", "icon": "" } } }
        """
        let result = try Migration.migrate(jsonData: Data(v1.utf8))
        let outData = Data(result.outputJSON.utf8)
        let root   = try #require(try JSONSerialization.jsonObject(with: outData) as? [String: Any])
        let spaces = try #require(root["spaces"] as? [String: Any])
        let slot1  = try #require(spaces["_unassigned:slot1"] as? [String: Any])
        let spec   = try #require(slot1["iconSpec"] as? [String: Any])
        #expect(spec["kind"]             as? String == "none")
        #expect(spec["fallbackSfSymbol"] as? String == "play.fill")
    }

    /// v2 → v3 preserves all existing iconSpec / color fields verbatim and
    /// only attaches the new composite-key envelope + displayUUID/workspaceName.
    @Test func v2_to_v3_preserves_color_and_icon() throws {
        let v2 = """
        {
          "version": 2,
          "spaces": {
            "5": {
              "name": "ai",
              "color": "#cdd6f4",
              "stableLogicalLabel": "ai",
              "iconSpec": {
                "kind": "sfSymbol",
                "symbolName": "brain",
                "userOverridden": true
              }
            }
          }
        }
        """
        let result = try Migration.migrate(jsonData: Data(v2.utf8))
        #expect(result.unassignedSlots == 1)

        let root = try #require(
            try JSONSerialization.jsonObject(with: Data(result.outputJSON.utf8)) as? [String: Any]
        )
        let spaces = try #require(root["spaces"] as? [String: Any])
        let slot = try #require(spaces["_unassigned:slot5"] as? [String: Any])
        #expect(slot["color"]         as? String == "#cdd6f4")
        #expect(slot["displayUUID"]   as? String == "_unassigned")
        #expect(slot["workspaceName"] as? String == "slot5")

        let spec = try #require(slot["iconSpec"] as? [String: Any])
        #expect(spec["kind"]           as? String == "sfSymbol")
        #expect(spec["symbolName"]     as? String == "brain")
        #expect(spec["userOverridden"] as? Bool   == true)
    }

    /// Idempotent: running migration on a v3 file produces no further touches.
    @Test func v3_is_idempotent() throws {
        let v1 = """
        { "version": 1, "spaces": { "1": { "name": "stream", "color": "#000000", "icon": "" } } }
        """
        let first  = try Migration.migrate(jsonData: Data(v1.utf8))
        let second = try Migration.migrate(jsonData: Data(first.outputJSON.utf8))
        #expect(second.alreadyV2,
                "v3 → v3 should report alreadyV2 (i.e. already at current version)")
        #expect(second.slotsTouched == 0)
        #expect(second.unassignedSlots == 0,
                "rewriting an _unassigned key shouldn't count it as freshly unassigned")
    }

    /// Every v2 slot lands in the `_unassigned:*` bucket — ws-topology
    /// reconciles them later against live aerospace workspaces.
    @Test func unassigned_bucket_carries_all_v2_slots() throws {
        let v2 = """
        {
          "version": 2,
          "spaces": {
            "1": { "name": "ws1", "color": "#111111", "iconSpec": { "kind": "none" }, "stableLogicalLabel": "ws1" },
            "2": { "name": "ws2", "color": "#222222", "iconSpec": { "kind": "none" }, "stableLogicalLabel": "ws2" },
            "7": { "name": "ws7", "color": "#777777", "iconSpec": { "kind": "none" }, "stableLogicalLabel": "ws7" }
          }
        }
        """
        let result = try Migration.migrate(jsonData: Data(v2.utf8))
        #expect(result.unassignedSlots == 3)

        let root = try #require(
            try JSONSerialization.jsonObject(with: Data(result.outputJSON.utf8)) as? [String: Any]
        )
        let spaces = try #require(root["spaces"] as? [String: Any])
        #expect(spaces.count == 3)
        #expect(spaces["_unassigned:slot1"] != nil)
        #expect(spaces["_unassigned:slot2"] != nil)
        #expect(spaces["_unassigned:slot7"] != nil)
    }

    /// Numerical key ordering carries into v3: `_unassigned:slot10` must
    /// appear after `_unassigned:slot9`, not after `_unassigned:slot1`.
    @Test func spaces_ordered_numerically() throws {
        var spaces: [String: Any] = [:]
        for i in 1...12 {
            spaces["\(i)"] = ["name": "ws\(i)", "color": "#000000", "icon": ""]
        }
        let root: [String: Any] = ["version": 1, "spaces": spaces]
        let data = try JSONSerialization.data(withJSONObject: root)
        let result = try Migration.migrate(jsonData: data)

        let nine    = try #require(result.outputJSON.range(of: "\"_unassigned:slot9\":"))
        let ten     = try #require(result.outputJSON.range(of: "\"_unassigned:slot10\":"))
        let twelve  = try #require(result.outputJSON.range(of: "\"_unassigned:slot12\":"))
        #expect(nine.lowerBound < ten.lowerBound)
        #expect(ten.lowerBound  < twelve.lowerBound)
    }
}

@Suite("Decoder preserves user-overridden flag across v3 round-trip")
struct RenamePreservesOverrideTests {
    /// The store decoder must preserve `userOverridden=true` across a load /
    /// re-save cycle — that's the invariant the postmortem demands. The
    /// workspace CLI's rename flow only touches `name`; `iconSpec` stays put.
    /// Now exercised against a v3 composite-key fixture.
    @Test func decoder_preserves_user_overridden_flag() throws {
        let v3 = """
        {
          "version": 3,
          "spaces": {
            "_unassigned:slot1": {
              "name": "custom",
              "color": "#abcdef",
              "stableLogicalLabel": "stream",
              "displayUUID": "_unassigned",
              "workspaceName": "slot1",
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
        #expect(slot.id                  == 1)
        #expect(slot.workspaceName       == "slot1")

        // Re-encode and verify the override survives + composite key reappears.
        let encoded = store.encodeJSON(config)
        #expect(encoded.contains("\"userOverridden\": true"))
        #expect(encoded.contains("\"symbolName\": \"star.fill\""))
        #expect(encoded.contains("\"_unassigned:slot1\""))
    }
}
