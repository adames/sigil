import Foundation
import Testing
@testable import WorkspaceState

/// Fixture-driven tests for AeroSpace's `--json` parsing. Doesn't talk
/// to a live daemon — exercises the Decodable layer against literal JSON
/// shapes that match `aerospace 0.20.x` output, plus the wire-type
/// projection. Bridging to CG displays is exercised indirectly through
/// fixtures that don't depend on which display is plugged in.
@Suite("AeroSpace JSON parsing")
struct AerospaceWindowManagerJSONTests {

    @Test func list_monitors_basic() throws {
        let json = #"""
        [
          {"monitor-id": 1, "monitor-name": "Built-in Retina Display"},
          {"monitor-id": 2, "monitor-name": "DELL U2723QE"}
        ]
        """#
        let monitors = try AerospaceWindowManager.decodeOrThrow(
            [AerospaceMonitor].self, from: json, label: "test"
        )
        #expect(monitors.count == 2)
        #expect(monitors[0].monitorId == 1)
        #expect(monitors[0].monitorName == "Built-in Retina Display")
        #expect(monitors[1].monitorId == 2)
        #expect(monitors[1].monitorName == "DELL U2723QE")
    }

    @Test func list_workspaces_all() throws {
        // monitor-name is present in aerospace's output but not decoded —
        // nothing downstream consumes it.
        let json = #"""
        [
          {"workspace": "1", "monitor-id": 1, "monitor-name": "Built-in"},
          {"workspace": "2", "monitor-id": 1, "monitor-name": "Built-in"},
          {"workspace": "A", "monitor-id": 2, "monitor-name": "DELL"}
        ]
        """#
        let spaces = try AerospaceWindowManager.decodeOrThrow(
            [AerospaceWorkspace].self, from: json, label: "test"
        )
        #expect(spaces.count == 3)
        #expect(spaces[0].workspace == "1")
        #expect(spaces[0].monitorId == 1)
        #expect(spaces[2].workspace == "A")
        #expect(spaces[2].monitorId == 2)
    }

    @Test func list_workspaces_focused_tolerates_missing_monitor() throws {
        // AeroSpace `--focused` output may omit monitor-id when there's
        // no active display (rare but possible at cold boot).
        let json = #"""
        [{"workspace": "ai"}]
        """#
        let spaces = try AerospaceWindowManager.decodeOrThrow(
            [AerospaceWorkspace].self, from: json, label: "test"
        )
        #expect(spaces.count == 1)
        #expect(spaces[0].workspace == "ai")
        #expect(spaces[0].monitorId == 1, "defaults to monitor 1 when absent")
    }

    @Test func list_windows_basic() throws {
        let json = #"""
        [
          {
            "window-id": 12345,
            "app-name": "Safari",
            "app-bundle-id": "com.apple.Safari",
            "window-title": "Sigil — GitHub",
            "workspace": "1",
            "monitor-id": 1
          },
          {
            "window-id": 67890,
            "app-name": "Terminal",
            "window-title": ""
          }
        ]
        """#
        let windows = try AerospaceWindowManager.decodeOrThrow(
            [AerospaceWindow].self, from: json, label: "test"
        )
        #expect(windows.count == 2)
        #expect(windows[0].windowId == 12345)
        #expect(windows[0].appName == "Safari")
        #expect(windows[0].windowTitle == "Sigil — GitHub")
        #expect(windows[0].workspace == "1")
        #expect(windows[0].monitorId == 1)
        #expect(windows[1].appBundleId == nil)
        #expect(windows[1].monitorId == nil)
    }

    @Test func malformed_json_surfaces_parse_error() throws {
        let junk = "not json"
        #expect(throws: WindowManagerError.self) {
            _ = try AerospaceWindowManager.decodeOrThrow(
                [AerospaceMonitor].self, from: junk, label: "test"
            )
        }
    }

    /// The wire-type projection: workspace name and monitor carry
    /// through; app falls back name → bundle-id → "Unknown".
    @Test func window_projection_preserves_workspace_and_fallbacks() throws {
        let json = #"""
        [
          {
            "window-id": 12345,
            "app-name": "Safari",
            "window-title": "Sigil — GitHub",
            "workspace": "code",
            "monitor-id": 2
          },
          {"window-id": 1, "app-bundle-id": "com.example.tool"},
          {"window-id": 2}
        ]
        """#
        let infos = try AerospaceWindowManager.decodeOrThrow(
            [AerospaceWindow].self, from: json, label: "test"
        ).map(AerospaceWindowManager.windowInfo(from:))

        #expect(infos[0].workspace == "code")
        #expect(infos[0].display == 2)
        #expect(infos[0].title == "Sigil — GitHub")
        #expect(infos[1].app == "com.example.tool")
        #expect(infos[2].app == "Unknown")
        #expect(infos[2].workspace == "")
        #expect(infos[2].display == 1, "missing monitor-id defaults to 1")
    }

    /// uuidForMonitor returns "" when the AeroSpace monitor-id isn't in
    /// the live monitor list — keeps callers safe under hot-plug races.
    @Test func uuid_for_unknown_monitor_returns_empty() {
        let uuid = AerospaceWindowManager.uuidForMonitor(
            id: 99,
            monitors: [
                AerospaceMonitor(
                    monitorId: 1, monitorName: "Built-in"
                ),
            ],
            cgDisplays: [:]
        )
        #expect(uuid == "")
    }
}

