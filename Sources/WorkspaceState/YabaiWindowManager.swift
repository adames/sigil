import Foundation

/// WindowManager implementation for yabai (https://github.com/koekeishiya/yabai)
public final class YabaiWindowManager: WindowManager {
    public static let kind: WindowManagerKind = .yabai
    
    public let binaryPath: String
    
    public init(binaryPath: String? = nil) {
        self.binaryPath = binaryPath ?? "/opt/homebrew/bin/yabai"
    }
    
    // MARK: - Space Operations

    public func focusSpace(target: WorkspaceTarget) throws {
        let slot = try resolveSlot(for: target)
        try runYabai(args: ["-m", "space", "--focus", "\(slot)"])
    }

    public func sendWindowToSpace(target: WorkspaceTarget, follow: Bool) throws {
        let slot = try resolveSlot(for: target)
        let windowID = try focusedWindowID()
        try runYabai(args: ["-m", "window", "--space", "\(slot)"])
        if follow, let wid = windowID {
            try focusWindow(id: wid)
        }
    }

    public func createSpace() throws -> WorkspaceTarget {
        try runYabai(args: ["-m", "space", "--create"])
        // The new space is the last one. Synthesize a target for it.
        let newSlot = try spaceCount()
        return WorkspaceTarget(
            displayUUID: "yabai-display-unknown",
            workspaceName: "slot\(newSlot)"
        )
    }

    public func destroySpace(target: WorkspaceTarget) throws {
        let slot = try resolveSlot(for: target)
        try runYabai(args: ["-m", "space", "\(slot)", "--destroy"])
    }

    public func focusedSpace() throws -> WorkspaceTarget? {
        guard let idx = try focusedSpaceIndex() else { return nil }
        // Yabai-era target identity is positional: same name-synthesis rule
        // as SpaceInfo's decoder.
        return WorkspaceTarget(
            displayUUID: "yabai-display-unknown",
            workspaceName: "slot\(idx)"
        )
    }

    public func focusedSpaceIndex() throws -> Int? {
        guard let output = try runYabaiWithOutput(args: ["-m", "query", "--spaces", "--space"]) else {
            return nil
        }
        guard let data = output.data(using: .utf8) else { return nil }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["index"] as? Int
    }

    public func spaceCount() throws -> Int {
        guard let output = try runYabaiWithOutput(args: ["-m", "query", "--spaces"]) else {
            return 0
        }
        guard let data = output.data(using: .utf8) else { return 0 }
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        return json?.count ?? 0
    }

    /// Translate a `WorkspaceTarget` back to a yabai global slot index.
    /// Yabai's space identity is positional, so `workspaceName` follows
    /// the "slot<N>" synthesis convention SpaceInfo's decoder uses.
    /// Targets carrying a custom name (set by ws-prompt rename) are
    /// resolved by walking `querySpaces()` and matching `label`.
    private func resolveSlot(for target: WorkspaceTarget) throws -> Int {
        if target.workspaceName.hasPrefix("slot"),
           let n = Int(target.workspaceName.dropFirst("slot".count)) {
            return n
        }
        let spaces = try querySpaces()
        if let match = spaces.first(where: { $0.workspaceName == target.workspaceName }) {
            return match.index
        }
        throw WindowManagerError.parseError(
            "yabai: no slot matches workspaceName=\(target.workspaceName)"
        )
    }
    
    // MARK: - Window Operations
    
    public func focusedWindowID() throws -> Int? {
        guard let output = try runYabaiWithOutput(args: ["-m", "query", "--windows", "--window"]) else {
            return nil
        }
        guard let data = output.data(using: .utf8) else { return nil }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["id"] as? Int
    }
    
    public func focusWindow(id: Int) throws {
        try runYabai(args: ["-m", "window", "--focus", "\(id)"])
    }

    // MARK: - Read-side queries

    public func queryDisplays() throws -> [DisplayInfo] {
        return try decodeQuery([DisplayInfo].self, args: ["-m", "query", "--displays"])
    }

    public func queryWindows() throws -> [WindowInfo] {
        return try decodeQuery([WindowInfo].self, args: ["-m", "query", "--windows"])
    }

    public func querySpaces() throws -> [SpaceInfo] {
        return try decodeQuery([SpaceInfo].self, args: ["-m", "query", "--spaces"])
    }

    /// Shared run+decode path for the read-side queries. yabai's stderr
    /// is dropped (matches `runYabaiWithOutput`); a non-zero exit
    /// surfaces as `commandFailed`, a parse error as `parseError`.
    private func decodeQuery<T: Decodable>(
        _ type: T.Type, args: [String]
    ) throws -> T {
        guard let output = try runYabaiWithOutput(args: args),
              let data = output.data(using: .utf8) else {
            throw WindowManagerError.commandFailed(
                "yabai \(args.joined(separator: " ")): no output"
            )
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw WindowManagerError.parseError(
                "yabai \(args.joined(separator: " ")): \(error)"
            )
        }
    }

    // MARK: - Private Helpers
    
    private func runYabai(args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let error = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WindowManagerError.commandFailed("yabai \(args.joined(separator: " ")): \(error)")
        }
    }
    
    private func runYabaiWithOutput(args: [String]) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            return nil
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
