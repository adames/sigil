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
// 3. `spaces.json` v3 schema (composite-key, AeroSpace-native):
//
//    {
//      "version": 3,
//      "spaces": {
//        "<displayUUID>:<workspaceName>": {
//          "displayUUID": "<CG-stable UUID>",
//          "workspaceName": "<aerospace name>",
//          "color": "#rrggbb",
//          "iconSpec": { ... }
//        }
//      }
//    }
//
//    `displayUUID` is `CGDisplayCreateUUIDFromDisplayID(...)` — the same
//    identifier `DisplayTopology.stableUUID(for:)` already produces.
//    AeroSpace's monitor ordinal is NOT stable across hot-plug; never key
//    on it. Inputs at version != 3 (v1, v2, or anything higher) raise
//    `MigrationError.unsupportedVersion` — there's no upgrade path.

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

/// AeroSpace binary discovery. `AEROSPACE_BIN` env var wins when set
/// (test harnesses use this to point at a stub); otherwise the first
/// installed Homebrew path. AeroSpace is the only backend post-migration —
/// `WORKSPACE_WINDOW_MANAGER` is no longer consulted.
public enum WindowManagerConfig {
    public static let binaryPath: String = {
        let env = ProcessInfo.processInfo.environment
        if let override = env["AEROSPACE_BIN"], !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        let candidates = [
            "/opt/homebrew/bin/aerospace",
            "/usr/local/bin/aerospace",
        ]
        for path in candidates
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return candidates.first ?? ""
    }()
}
