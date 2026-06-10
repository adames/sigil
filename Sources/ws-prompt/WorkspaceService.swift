import Foundation

/// The single seam between the controller and the outside world.
///
/// Everything that talks to aerospace, the `ws` CLI, or the file system
/// goes through this protocol — `Process()` invocations, reads of
/// `~/.config/workspace/spaces.json`, invocations of helper scripts. The
/// production implementation (`ProductionWorkspaceService`) does the real
/// thing; the boundary keeps WsPromptApp decoupled from that I/O (and
/// substitutable in principle). Nothing automated drives the end-to-end
/// path today — `--simulate-keys` exists for manual smoke-testing.
protocol WorkspaceService {
    // MARK: Sync reads
    func loadWorkspaces() -> [Workspace]

    // MARK: Fire-and-forget helper (no panel — spawns ws-send-follow)
    func spawnSend(slot: Int)
}
