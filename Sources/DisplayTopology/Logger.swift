import Foundation
import OSLog
import WorkspaceState

public enum TopologyLog {
    public static let subsystem = WorkspaceSystem.logSubsystem

    public static let topology = Logger(subsystem: subsystem, category: "topology")
    public static let policy   = Logger(subsystem: subsystem, category: "policy")
}
