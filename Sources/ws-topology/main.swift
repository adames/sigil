import AerospaceEmit
import AppKit
import CoreGraphics
import DisplayTopology
import Foundation
import LayoutPolicy
import OSLog
import WorkspaceState

// MARK: - Entry point

let args = Array(CommandLine.arguments.dropFirst())
let exitCode = run(args: args)
exit(exitCode)

func run(args: [String]) -> Int32 {
    guard let subcommand = args.first else {
        printUsage()
        return 2
    }

    let rest = Array(args.dropFirst())

    switch subcommand {
    case "dump":            return cmdDump(args: rest)
    case "layout":          return cmdLayout(args: rest)
    case "migrate":         return cmdMigrate(args: rest)
    case "resolve-icon":    return cmdResolveIcon(args: rest)
    case "emit-aerospace":  return cmdEmitAerospace(args: rest)
    case "help", "-h", "--help":
        printUsage()
        return 0
    default:
        FileHandle.standardError.write(Data("ws-topology: unknown subcommand: \(subcommand)\n".utf8))
        printUsage()
        return 2
    }
}

func printUsage() {
    let usage = """
    usage: ws-topology <subcommand> [args]

      dump                        print the current display topology as JSON
      layout                      print the per-display layout policy as JSON
      migrate [--apply]           validate + canonically re-render spaces.json
                                  (dry-run by default). v3 only; v1/v2 inputs error.
      resolve-icon <slot>         resolve the icon for a workspaceName / slot name / 1-based ordinal; --surface=font|native
      emit-aerospace [--write]    emit the sigil-fenced aerospace.toml block.
                                  --write: merge into ~/.config/aerospace/aerospace.toml.
                                  --reload: call `aerospace reload-config` after writing.
                                  --dry-run: print to stdout (default with no --write).
                                  --validate: run `aerospace reload-config --dry-run` after
                                  the merge, rolling back on rejection; skipped if the
                                  daemon is unreachable.

    common flags (migrate / resolve-icon / emit-aerospace):
      --config PATH         override spaces.json location (default ~/.config/workspace/spaces.json)

    """
    FileHandle.standardError.write(Data(usage.utf8))
}

// MARK: - Common arg parsing

struct CommonOptions {
    var configURL: URL
    var remaining: [String]
}

func parseCommonOptions(_ args: [String]) -> CommonOptions {
    let home = FileManager.default.homeDirectoryForCurrentUser
    var configPath = ProcessInfo.processInfo.environment["WS_CONFIG"]
        ?? home.appendingPathComponent(".config/workspace/spaces.json").path

    var remaining: [String] = []
    var i = 0
    while i < args.count {
        let a = args[i]
        if a == "--config", i + 1 < args.count {
            configPath = args[i+1]; i += 2; continue
        }
        remaining.append(a); i += 1
    }
    return CommonOptions(
        configURL: URL(fileURLWithPath: configPath),
        remaining: remaining
    )
}

// MARK: - dump

func cmdDump(args: [String]) -> Int32 {
    return MainActor.assumeIsolated {
        let snapshot = DisplayTopologyService.snapshot()
        do {
            let json = try CacheEncoding.encode(snapshot)
            print(json)
            return 0
        } catch {
            FileHandle.standardError.write(Data("dump: \(error)\n".utf8))
            return 1
        }
    }
}

// MARK: - layout

func cmdLayout(args: [String]) -> Int32 {
    return MainActor.assumeIsolated {
        let snapshot = DisplayTopologyService.snapshot()
        let policies = LayoutPolicyEngine.policies(for: snapshot.displays)
        do {
            let json = try CacheEncoding.encode(policies)
            print(json)
            return 0
        } catch {
            FileHandle.standardError.write(Data("layout: \(error)\n".utf8))
            return 1
        }
    }
}

// MARK: - migrate
//
// The v1 → v2 → v3 transformation chain retired with the AeroSpace
// migration. This subcommand is now a validator + canonical re-renderer:
// it rejects anything other than v3 and re-writes the file with
// deterministic key ordering. Mostly useful for jq-friendlying a
// hand-edited spaces.json after manual repairs.

func cmdMigrate(args: [String]) -> Int32 {
    let opts = parseCommonOptions(args)
    let apply = opts.remaining.contains("--apply")

    let data: Data
    do {
        data = try Data(contentsOf: opts.configURL)
    } catch {
        FileHandle.standardError.write(Data("migrate: cannot read \(opts.configURL.path): \(error)\n".utf8))
        return 1
    }

    let result: MigrationResult
    do {
        result = try Migration.migrate(jsonData: data)
    } catch {
        FileHandle.standardError.write(Data("migrate: \(error)\n".utf8))
        return 1
    }

    if !apply {
        FileHandle.standardError.write(Data("# DRY RUN — pass --apply to write the canonicalized JSON back.\n".utf8))
        print(result.outputJSON, terminator: "")
        return 0
    }

    do {
        try CacheEncoding.atomicWrite(result.outputJSON, to: opts.configURL)
    } catch {
        FileHandle.standardError.write(Data("migrate: write failed: \(error)\n".utf8))
        return 1
    }
    FileHandle.standardError.write(Data("migrate: re-rendered spaces.json (v\(Migration.currentVersion))\n".utf8))
    return 0
}

// MARK: - resolve-icon

func cmdResolveIcon(args: [String]) -> Int32 {
    let opts = parseCommonOptions(args)
    var surface: IconTargetSurface = .textBased
    var slotArg: String? = nil

    for arg in opts.remaining {
        if arg == "--surface=font" || arg == "--surface=font-driven" {
            surface = .textBased
        } else if arg == "--surface=native" || arg == "--surface=appkit" {
            surface = .nativeAppKit
        } else if !arg.hasPrefix("--") {
            slotArg = arg
        }
    }

    guard let slotArg else {
        FileHandle.standardError.write(Data("resolve-icon: missing slot argument (index or name)\n".utf8))
        return 2
    }

    let store = WorkspaceStateStore(configURL: opts.configURL)
    let config: WorkspaceConfig
    do {
        config = try store.load()
    } catch {
        FileHandle.standardError.write(Data("resolve-icon: \(error)\n".utf8))
        return 1
    }

    // Resolve the arg in priority order:
    //   1. matches a workspaceName exactly (the v3 canonical identity)
    //   2. matches a slot.name (case-insensitive — user-facing label)
    //   3. parses as a 1-based ordinal into spaces.json's sorted order
    //
    // Order #1 wins on tie because workspaceName is the routing key the
    // chord layer + aerospace.toml use, and order #2 is the label the
    // pill renders. A digit string falls through to #3 only when no
    // workspaceName matches it — preserves "resolve-icon 1" for legacy
    // callers without breaking aerospace deployments where "1" is a
    // real workspace name.
    let slot: WorkspaceSlot? = {
        if let direct = config.slots.first(where: { $0.workspaceName == slotArg }) {
            return direct
        }
        if let labeled = config.slots.first(where: { $0.name.lowercased() == slotArg.lowercased() }) {
            return labeled
        }
        if let idx = Int(slotArg), idx >= 1, idx <= config.slots.count {
            return config.slots[idx - 1]
        }
        return nil
    }()
    guard let slot else {
        FileHandle.standardError.write(Data("resolve-icon: no slot matches '\(slotArg)' (try a workspaceName, slot name, or 1-based ordinal)\n".utf8))
        return 1
    }

    let resolved = IconResolver.resolve(
        spec: slot.iconSpec,
        targetSurface: surface,
        sfSymbolExists: SfSymbolAvailability.exists(_:)
    )

    let json: [String: Any] = [
        "workspaceName": slot.workspaceName,
        "displayUUID":   slot.displayUUID,
        "name":          slot.name,
        "kind":  resolved.kind.rawValue,
        "value": resolved.value,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
        print(String(decoding: data, as: UTF8.self))
    }
    return 0
}

// MARK: - Supporting helpers

enum SfSymbolAvailability {
    static func exists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}

// MARK: - emit-aerospace
//
// The fenced-block renderer + merge engine lives in the AerospaceEmit
// library target (Sources/AerospaceEmit) so the test suite exercises the
// production implementation.

func cmdEmitAerospace(args: [String]) -> Int32 {
    let opts = parseCommonOptions(args)
    let write = opts.remaining.contains("--write")
    let reload = opts.remaining.contains("--reload")
    let validate = opts.remaining.contains("--validate")
    let dryRun = opts.remaining.contains("--dry-run")
    let aerospaceBin = ProcessInfo.processInfo.environment["AEROSPACE_BIN"]
        ?? "/opt/homebrew/bin/aerospace"

    let store = WorkspaceStateStore(configURL: opts.configURL)
    let config: WorkspaceConfig
    do {
        config = try store.load()
    } catch {
        FileHandle.standardError.write(Data("emit-aerospace: \(error)\n".utf8))
        return 1
    }

    // workspaceName is the binding target — names are stable, ordinals
    // aren't. Slot ordering follows spaces.json composite-key sort.
    let names = config.slots.map(\.workspaceName)
    let bindingsBlock   = AerospaceFragment.render(slotNames: names)
    let assignmentBlock = AerospaceFragment.renderAssignmentBlock(slotNames: names)

    if !write || dryRun {
        print(assignmentBlock, terminator: "")
        print("")
        print(bindingsBlock, terminator: "")
        return 0
    }

    let target = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/aerospace/aerospace.toml")
    let fileExisted = FileManager.default.fileExists(atPath: target.path)
    let existing: String = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
    // Assignments first (top-level), then bindings (inside [mode.main.binding]).
    let merged: String
    do {
        let afterAssign = try AerospaceFragment.merge(
            block: assignmentBlock,
            into: existing,
            openFence: AerospaceFragment.assignmentOpenFence,
            closeFence: AerospaceFragment.assignmentCloseFence
        )
        merged = try AerospaceFragment.merge(block: bindingsBlock, into: afterAssign)
    } catch {
        FileHandle.standardError.write(Data("emit-aerospace: \(error)\n".utf8))
        return 1
    }

    do {
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try CacheEncoding.atomicWrite(merged, to: target)
        FileHandle.standardError.write(Data("emit-aerospace: wrote \(target.path)\n".utf8))
    } catch {
        FileHandle.standardError.write(Data("emit-aerospace: write failed: \(error)\n".utf8))
        return 1
    }

    // Validation runs AFTER the write: `aerospace reload-config --dry-run`
    // only checks the config at its fixed path (there is no flag to point
    // it at a candidate file), so the merged result must be on disk. On
    // rejection the previous content is restored.
    if validate {
        switch validateAerospace(aerospaceBin: aerospaceBin) {
        case .ok:
            FileHandle.standardError.write(Data("emit-aerospace: validation passed\n".utf8))
        case .daemonUnreachable:
            FileHandle.standardError.write(Data("emit-aerospace: aerospace daemon not running — skipping validation\n".utf8))
        case .rejected(let stderr):
            FileHandle.standardError.write(Data("emit-aerospace: validation failed, rolling back:\n\(stderr)\n".utf8))
            do {
                if fileExisted {
                    try CacheEncoding.atomicWrite(existing, to: target)
                } else {
                    try FileManager.default.removeItem(at: target)
                }
            } catch {
                FileHandle.standardError.write(Data("emit-aerospace: rollback failed: \(error)\n".utf8))
            }
            return 1
        }
    }

    if reload {
        let rc = runAerospaceReload(aerospaceBin: aerospaceBin)
        if rc != 0 {
            FileHandle.standardError.write(Data("emit-aerospace: reload-config returned \(rc)\n".utf8))
            // Distinct from validation/write failures: the config was
            // written but never loaded — scripted callers need to see it.
            return 3
        }
    }
    return 0
}

enum AerospaceValidation {
    case ok
    case daemonUnreachable
    case rejected(stderr: String)
}

/// Dry-run `aerospace reload-config` against the on-disk config.
/// AeroSpace 0.20+ exposes --dry-run on reload-config but no way to point
/// it at a candidate file, so the caller writes first and rolls back on
/// `.rejected`. If the daemon isn't running we surface
/// `.daemonUnreachable` rather than fail — fresh-install bootstrap may
/// emit the block before the .app starts.
func validateAerospace(aerospaceBin: String) -> AerospaceValidation {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: aerospaceBin)
    proc.arguments = ["reload-config", "--dry-run", "--no-gui"]
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    proc.standardOutput = stdoutPipe
    proc.standardError = stderrPipe
    do {
        try proc.run()
    } catch {
        return .daemonUnreachable
    }
    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    if proc.terminationStatus == 0 {
        return .ok
    }
    let err = String(data: errData, encoding: .utf8) ?? ""
    // "Can't connect to AeroSpace server" is the daemon-not-running signature.
    if err.contains("Can't connect to AeroSpace server") {
        return .daemonUnreachable
    }
    return .rejected(stderr: err)
}

@discardableResult
func runAerospaceReload(aerospaceBin: String) -> Int32 {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: aerospaceBin)
    proc.arguments = ["reload-config"]
    do {
        try proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus
    } catch {
        return -1
    }
}
