import Foundation

/// The single seam between the controller and the outside world.
///
/// Everything that talks to aerospace, the `ws` CLI, or the file system
/// goes through this protocol — `Process()` invocations, reads of
/// `~/.config/workspace/spaces.json`, invocations of helper scripts. The
/// production implementation (`ProductionWorkspaceService`) does the real
/// thing; tests inject a fake that records calls and returns canned data.
protocol WorkspaceService {
    // MARK: Sync reads
    func loadWorkspaces() -> [Workspace]

    // MARK: Fire-and-forget helpers (focus/send don't show a panel)
    func spawnFocus(slot: Int)
    func spawnSend(slot: Int)
}
