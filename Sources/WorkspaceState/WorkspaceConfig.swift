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
    public static let logSubsystem: String = "\(bundlePrefix).topology"
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
