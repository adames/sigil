import Foundation

public struct WorkspaceSlot: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var color: String
    public var iconSpec: IconSpec
    public var stableLogicalLabel: String
    /// CG-stable display UUID — `CGDisplayCreateUUIDFromDisplayID(…)`
    /// output. Required under v3; empty value is a construction bug.
    public var displayUUID: String
    /// AeroSpace workspace name under v3. Required; empty value is a
    /// construction bug. The decoder + encoder both round-trip on this.
    public var workspaceName: String

    public init(
        id: Int,
        name: String,
        color: String,
        iconSpec: IconSpec,
        stableLogicalLabel: String,
        displayUUID: String,
        workspaceName: String
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.iconSpec = iconSpec
        self.stableLogicalLabel = stableLogicalLabel
        self.displayUUID = displayUUID
        self.workspaceName = workspaceName
    }
}

public struct WorkspaceConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var palette: String?
    public var theme: String?
    public var slots: [WorkspaceSlot]

    public init(version: Int, palette: String?, theme: String?, slots: [WorkspaceSlot]) {
        self.version = version
        self.palette = palette
        self.theme = theme
        self.slots = slots
    }
}
