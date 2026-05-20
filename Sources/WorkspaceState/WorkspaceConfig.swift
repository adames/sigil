import Foundation

// MARK: - Migration contracts (frozen 2026-05-20)
//
// These three contracts are intentionally documented in source so anyone
// editing the workspace stack sees them before changing related code.
//
// 1. `current.env` schema (read by tmux + starship out of repo):
//    - export MACOS_WORKSPACE_NAME='<aerospace workspace name>'   (was MACOS_SPACE_INDEX)
//    - export MACOS_SPACE_NAME='<spaces.json identity name>'
//    - export MACOS_SPACE_COLOR='#rrggbb'
//    - export MACOS_SPACE_ICON='<glyph>'
//    - export MACOS_SPACE_DISPLAY=<aerospace monitor ordinal, 1..N>
//    - export MACOS_SPACE_ANSI='<pre-rendered truecolor sequence>'
//    Out-of-repo consumers (tmux.conf, starship.toml) only read NAME / COLOR
//    / ICON / ANSI today, so the INDEX→WORKSPACE_NAME rename has no external
//    fallout. Update any in-repo readers of MACOS_SPACE_INDEX in lockstep.
//
// 2. `~/.config/aerospace/aerospace.toml` ownership: hybrid sentinel-fenced.
//    User owns gaps, modes, on-window-detected, and all bindings *outside*
//    the fence. Sigil (`ws-topology emit-aerospace`) owns everything between:
//
//        # >>> sigil generated >>>
//        # <<< sigil generated <<<
//
//    Inside the fence: per-workspace `[mode.main.binding]` digit chords + the
//    `exec-on-workspace-change` cascade that replaces yabai's space_changed
//    signal. Missing fences ⇒ first-run appends both fence and content at EOF.
//    Hand-edits inside the fence are clobbered on next `ws-topology emit-aerospace`.
//
// 3. `spaces.json` v3 schema (composite-key, post-yabai):
//
//    {
//      "version": 3,
//      "spaces": {
//        "<displayUUID>:<workspaceName>": {
//          "displayUUID": "<CG-stable UUID>",
//          "workspaceName": "<aerospace name>",
//          "color": "#rrggbb",
//          "iconSpec": { ... }
//        },
//        "_unassigned:slot_<N>": { ... }   // transitional bucket post-migration
//      }
//    }
//
//    `displayUUID` is `CGDisplayCreateUUIDFromDisplayID(...)` — the same
//    identifier `DisplayTopology.stableUUID(for:)` already produces. AeroSpace's
//    monitor ordinal is NOT stable across hot-plug; never key on it.
//    v2-slot entries that survive migration land in `_unassigned:*` until
//    `ws-topology` reconciles them against live `aerospace list-workspaces`.

/// Central configuration for workspace system.
/// These values are read from environment variables at build time,
/// allowing customization without code changes.
public enum WorkspaceSystem {
    /// The bundle prefix for all workspace binaries.
    /// Override with WORKSPACE_BUNDLE_PREFIX env var at build time.
    /// Default: "com.user.workspace"
    public static let bundlePrefix: String = {
        ProcessInfo.processInfo.environment["WORKSPACE_BUNDLE_PREFIX"]
            ?? "com.user.workspace"
    }()
    
    /// The OSLog subsystem identifier.
    public static let logSubsystem: String = "\(bundlePrefix).topology"
    
    /// The LaunchAgent label prefix.
    public static let launchAgentPrefix: String = bundlePrefix
    
    /// Base paths - respect XDG conventions when possible
    public static let homeDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
    }()
    
    public static let configDirectory: URL = {
        if let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
            return URL(fileURLWithPath: xdgConfig).appendingPathComponent("workspace")
        }
        return homeDirectory.appendingPathComponent(".config/workspace")
    }()
    
    public static let cacheDirectory: URL = {
        if let xdgCache = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"] {
            return URL(fileURLWithPath: xdgCache).appendingPathComponent("workspace")
        }
        return homeDirectory.appendingPathComponent(".cache/workspace")
    }()
    
    public static let binDirectory: URL = {
        homeDirectory.appendingPathComponent(".local/bin")
    }()
    
    /// LaunchAgent directory
    public static let launchAgentsDirectory: URL = {
        homeDirectory.appendingPathComponent("Library/LaunchAgents")
    }()
    
    /// File names
    public static let spacesFileName: String = "spaces.json"
    public static let topologyFileName: String = "topology.json"
    public static let layoutEnvFileName: String = "layout.env"
    public static let currentEnvFileName: String = "current.env"
}

/// Window manager integration configuration. Post-Phase-6 there's only
/// one supported backend (AeroSpace); the env var still exists for
/// rare test setups that want to force `none`.
public enum WindowManagerConfig {
    /// The window manager to use. Override with WORKSPACE_WINDOW_MANAGER
    /// env var. Supported values: `"aerospace"` (default), `"none"`.
    /// Legacy values `"yabai"` and `"rectangle"` decode to a no-op
    /// backend during transition; logging surfaces remain quiet.
    public static let `default`: String = {
        ProcessInfo.processInfo.environment["WORKSPACE_WINDOW_MANAGER"]
            ?? "aerospace"
    }()

    /// Path to the aerospace binary. `AEROSPACE_BIN` env var wins when
    /// set (test harnesses use this to point at a stub).
    public static let binaryPath: String = {
        let env = ProcessInfo.processInfo.environment
        return resolveBinary(
            envVar: "AEROSPACE_BIN",
            candidates: [
                "/opt/homebrew/bin/aerospace",
                "/usr/local/bin/aerospace",
            ],
            env: env
        )
    }()

    private static func resolveBinary(
        envVar: String, candidates: [String], env: [String: String]
    ) -> String {
        if let override = env[envVar], !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        for path in candidates
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return candidates.first ?? ""
    }
}
