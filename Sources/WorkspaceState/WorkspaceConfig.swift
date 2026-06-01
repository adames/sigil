import Foundation

// MARK: - Contracts
//
// current.env keys (read by tmux + starship):
//   MACOS_WORKSPACE_NAME, MACOS_SPACE_NAME, MACOS_SPACE_COLOR,
//   MACOS_SPACE_ICON, MACOS_SPACE_DISPLAY, MACOS_SPACE_ANSI
//
// aerospace.toml ownership: user owns everything outside the sentinel fences;
//   ws-topology emit-aerospace owns the block between:
//     # >>> sigil generated >>>  …  # <<< sigil generated <<<
//
// spaces.json v3 key: "<displayUUID>:<workspaceName>"
//   displayUUID = CGDisplayCreateUUIDFromDisplayID — stable across reboots.
//   Never key on the aerospace monitor ordinal; it shifts on hot-plug.

public enum WorkspaceSystem {
    public static let bundlePrefix: String = {
        ProcessInfo.processInfo.environment["WORKSPACE_BUNDLE_PREFIX"]
            ?? "com.user.workspace"
    }()
    public static let logSubsystem: String    = "\(bundlePrefix).topology"
    public static let launchAgentPrefix: String = bundlePrefix

    public static let homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser

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

    public static let binDirectory: URL = homeDirectory.appendingPathComponent(".local/bin")
    public static let launchAgentsDirectory: URL = homeDirectory.appendingPathComponent("Library/LaunchAgents")

    public static let spacesFileName: String   = "spaces.json"
    public static let topologyFileName: String = "topology.json"
    public static let layoutEnvFileName: String = "layout.env"
    public static let currentEnvFileName: String = "current.env"
}

/// AeroSpace binary path. `AEROSPACE_BIN` env var overrides (test harnesses use this).
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
