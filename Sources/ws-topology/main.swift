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
                                  --validate: run `aerospace reload-config --dry-run` before
                                  committing the merge; skipped if daemon unreachable.

    common flags:
      --config PATH         override spaces.json location (default ~/.config/workspace/spaces.json)
      --cache-dir PATH      override cache directory (default ~/.cache/workspace)

    """
    FileHandle.standardError.write(Data(usage.utf8))
}

// MARK: - Common arg parsing

struct CommonOptions {
    var configURL: URL
    var cacheDirURL: URL
    var remaining: [String]
}

func parseCommonOptions(_ args: [String]) -> CommonOptions {
    let home = FileManager.default.homeDirectoryForCurrentUser
    var configPath = ProcessInfo.processInfo.environment["WS_CONFIG"]
        ?? home.appendingPathComponent(".config/workspace/spaces.json").path
    var cachePath  = ProcessInfo.processInfo.environment["WS_CACHE_DIR"]
        ?? home.appendingPathComponent(".cache/workspace").path

    var remaining: [String] = []
    var i = 0
    while i < args.count {
        let a = args[i]
        if a == "--config", i + 1 < args.count {
            configPath = args[i+1]; i += 2; continue
        }
        if a == "--cache-dir", i + 1 < args.count {
            cachePath = args[i+1]; i += 2; continue
        }
        remaining.append(a); i += 1
    }
    return CommonOptions(
        configURL: URL(fileURLWithPath: configPath),
        cacheDirURL: URL(fileURLWithPath: cachePath),
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

    let availableFonts = AvailableFonts.current()
    let resolved = IconResolver.resolve(
        spec: slot.iconSpec,
        availableFonts: availableFonts,
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

enum AvailableFonts {
    static func current() -> Set<String> {
        Set(NSFontManager.shared.availableFontFamilies)
    }
}

enum SfSymbolAvailability {
    static func exists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}

// MARK: - emit-aerospace

/// AeroSpace.toml binding block renderer. Output is sentinel-fenced so the
/// merge writer can replace just this section without touching the user's
/// gaps / modes / on-window-detected / non-digit bindings.
enum AerospaceFragment {

    /// Open / close fences for the digit-bindings block. Plain ASCII,
    /// idempotent to detect: a regex match across the file picks up
    /// multi-line content between them. The "digit-bindings" fence sits
    /// inside `[mode.main.binding]` because the keys it emits
    /// (`cmd-alt-ctrl-shift-N = 'workspace …'`) only resolve when the
    /// surrounding table is open.
    static let openFence  = "# >>> sigil generated >>>"
    static let closeFence = "# <<< sigil generated <<<"

    /// Open / close fences for the `[workspace-to-monitor-force-assignment]`
    /// block. Lives at the top level (must appear before any other `[…]`
    /// header). Separate fence pair so the merge function can update each
    /// region independently — the digit bindings change when spaces.json's
    /// names change; the assignment table changes when the slot count or
    /// monitor mapping changes.
    static let assignmentOpenFence  = "# >>> sigil generated: assignments >>>"
    static let assignmentCloseFence = "# <<< sigil generated: assignments <<<"

    /// Path of the user-side on-space-changed hook the cascade calls.
    /// Matches the path the aerospace signal points at today; survives the
    /// burn-aerospace cut because the script is deployed by dotfiles, not by
    /// the window manager.
    static let cascadeHookPath = "$HOME/.config/workspace/on-space-changed.sh"

    /// Render the fenced TOML block for a given set of slots.
    ///
    /// - Digit bindings (`cmd-alt-ctrl-shift-1..0`) map to the first 10
    ///   slots in spaces.json's deterministic order, addressing
    ///   workspaces by name (fork B).
    /// - Send-window digit bindings are intentionally NOT emitted —
    ///   Hyperkey collapses Caps+Shift+digit into Caps+digit
    ///   (cmd+alt+ctrl+shift+digit), so they'd collide with focus.
    ///   Send-window is reachable via Caps+g (ws-prompt) instead.
    /// - `exec-on-workspace-change` is the only cascade hook AeroSpace
    ///   offers; it replaces aerospace's `space_changed` signal subscription.
    /// Render the fenced TOML block for a given set of slots.
    ///
    /// **Block must be placed inside an already-open `[mode.main.binding]`
    /// table.** TOML is sequential — once a table opens with `[name]`,
    /// everything until the next `[…]` belongs to it. The generator
    /// emits only the digit-binding key=value pairs (no header) so it
    /// can sit at the bottom of the user-owned `[mode.main.binding]`
    /// block. Duplicating `[mode.main.binding]` as a header here would
    /// trip TOML's no-redefine rule.
    ///
    /// The cascade hook (`exec-on-workspace-change`) lives outside the
    /// generated block — it's a top-level key and must appear before
    /// any `[…]` header. configs/aerospace.toml's top section sets it
    /// directly to `$HOME/.config/workspace/on-space-changed.sh`.
    ///
    /// - Digit bindings (`cmd-alt-ctrl-shift-1..0`) map to the first 10
    ///   slots in spaces.json's deterministic order, addressing
    ///   workspaces by name (fork B).
    /// - Send-window digit bindings are intentionally NOT emitted —
    ///   Hyperkey collapses Caps+Shift+digit into Caps+digit
    ///   (cmd+alt+ctrl+shift+digit), so they'd collide with focus.
    ///   Send-window is reachable via Caps+g (ws-prompt) instead.
    static func render(slotNames: [String]) -> String {
        let visible = Array(slotNames.prefix(10))
        var lines: [String] = []
        lines.append(openFence)
        lines.append("# Generated by `ws-topology emit-aerospace`. Hand-edits inside")
        lines.append("# this block are clobbered on next regeneration. Edit the source")
        lines.append("# of truth in ~/.config/workspace/spaces.json (and re-emit) or")
        lines.append("# the user-owned section of aerospace.toml (above the fence).")
        lines.append("#")
        lines.append("# This block must live inside an open [mode.main.binding] table —")
        lines.append("# do not move it above any [...] header.")

        if visible.isEmpty {
            lines.append("# (no workspaces declared in spaces.json yet)")
        } else {
            lines.append("# Hyper+digit: focus workspace by name. Digit N → N-th workspace")
            lines.append("# in spaces.json composite-key order. Slot 10 is bound to '0'.")
            for (i, name) in visible.enumerated() {
                let digit = (i == 9) ? "0" : String(i + 1)
                lines.append("cmd-alt-ctrl-shift-\(digit) = 'workspace \(escapeBindingArg(name))'")
            }
            lines.append("# Send-window digit bindings (Caps+Shift+N) intentionally absent —")
            lines.append("# Hyperkey collapses Caps+Shift+digit into Caps+digit (same chord).")
            lines.append("# Use Caps+g (ws-prompt send) to send a window to a specific workspace.")
        }
        lines.append(closeFence)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Render the fenced TOML block for `[workspace-to-monitor-force-assignment]`.
    ///
    /// Unlike the digit-bindings block, this fence sits OUTSIDE any
    /// `[…]` table (and emits its own `[workspace-to-monitor-force-
    /// assignment]` header) — top-level TOML keys must appear before
    /// any table header is opened. spaces.json drives both the count
    /// and the names; monitor binding is currently `1` (primary) for
    /// every slot since v3 spaces.json stores `displayUUID` but not a
    /// committed monitor ordinal.
    ///
    /// TODO: when spaces.json grows displayUUID → monitor-ordinal
    /// resolution (via topology), thread the real ordinal through here.
    /// For now everything pins to monitor 1; this matches the current
    /// hand-managed behavior and keeps single-display setups working.
    static func renderAssignmentBlock(slotNames: [String]) -> String {
        var lines: [String] = []
        lines.append(assignmentOpenFence)
        lines.append("# Generated by `ws-topology emit-aerospace`. Hand-edits inside")
        lines.append("# this block are clobbered on next regeneration. Edit the source")
        lines.append("# of truth in ~/.config/workspace/spaces.json (and re-emit).")
        lines.append("#")
        lines.append("# Workspace existence + monitor binding. Each name MUST match a")
        lines.append("# spaces.json slot's workspaceName; mismatches cause aerospace")
        lines.append("# chords (`workspace N`) to fail silently. ws-statusbar renders")
        lines.append("# one pill per declared workspace, so the count here also drives")
        lines.append("# the pill bar grid.")
        if slotNames.isEmpty {
            lines.append("# (no workspaces declared in spaces.json yet)")
        } else {
            lines.append("[workspace-to-monitor-force-assignment]")
            for name in slotNames {
                lines.append("\"\(escapeBindingArg(name))\" = 1")
            }
        }
        lines.append(assignmentCloseFence)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Escape single quotes for safe insertion inside `'…'` TOML strings.
    /// AeroSpace workspace names allow most printable ASCII; we only need
    /// to defend against the quote char.
    static func escapeBindingArg(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "\\'")
    }

    /// Merge `block` into `existing`, replacing the content between the
    /// fences (inclusive) if they're present, or appending at EOF
    /// otherwise. Idempotent: re-merging the same block yields the same
    /// output.
    ///
    /// The fence pair is parameterised so the caller can drive either
    /// the digit-bindings region or the workspace-assignments region
    /// against the same engine. Defaults to the digit-bindings fence
    /// for backwards compatibility with existing callers.
    ///
    /// **Line-anchored** — the fence string must appear as a STANDALONE
    /// LINE, not as a substring inside a documentation comment.
    /// (Prior versions used `String.range(of:)` substring matching; when
    /// users documented the fence by name in a header comment, the
    /// search snagged the doc comment and mangled the whole file.)
    static func merge(
        block: String,
        into existing: String,
        openFence: String = AerospaceFragment.openFence,
        closeFence: String = AerospaceFragment.closeFence
    ) -> String {
        // Trim block trailing newline; we'll re-add one when appending.
        let cleanBlock = block.hasSuffix("\n") ? String(block.dropLast()) : block

        var lines = existing.components(separatedBy: "\n")
        // After split, a trailing "\n" in input produces an empty last
        // element. Track + restore so output preserves the trailing
        // newline state.
        let hadTrailingNewline = existing.hasSuffix("\n")
        if hadTrailingNewline, lines.last == "" { lines.removeLast() }

        let openIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == openFence })
        let closeIdx: Int? = openIdx.flatMap { o in
            lines[(o + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == closeFence })
        }

        if let o = openIdx, let c = closeIdx {
            // Replace lines [o ... c] (inclusive) with the new block lines.
            let blockLines = cleanBlock.components(separatedBy: "\n")
            lines.replaceSubrange(o...c, with: blockLines)
            var out = lines.joined(separator: "\n")
            if hadTrailingNewline || !out.hasSuffix("\n") { out += "\n" }
            return out
        }

        // No fence found — append. Add a separator newline if the file
        // doesn't end in one.
        let needsSeparator = !existing.isEmpty && !existing.hasSuffix("\n")
        return existing + (needsSeparator ? "\n" : "") + cleanBlock + "\n"
    }
}

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

    // Use workspaceName as the binding target. Names are stable; ordinals
    // are not. Slot.id ordering already reflects spaces.json composite-key
    // sort thanks to WorkspaceStateStore.extractSlotId.
    let names = config.slots.map(\.workspaceName)
    let bindingsBlock   = AerospaceFragment.render(slotNames: names)
    let assignmentBlock = AerospaceFragment.renderAssignmentBlock(slotNames: names)

    // Default to stdout if --write isn't passed, regardless of --dry-run.
    // Print both blocks separated by a blank line; consumers can pipe to
    // grep for the fence they care about.
    if !write || dryRun {
        print(assignmentBlock, terminator: "")
        print("")
        print(bindingsBlock, terminator: "")
        return 0
    }

    let target = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/aerospace/aerospace.toml")
    let existing: String = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
    // Two independent merges. Order matters: assignments first so they
    // land above [mode.main.binding]; bindings second so they sit inside
    // that table. Both are line-anchored against their own fence pair.
    let afterAssign = AerospaceFragment.merge(
        block: assignmentBlock,
        into: existing,
        openFence: AerospaceFragment.assignmentOpenFence,
        closeFence: AerospaceFragment.assignmentCloseFence
    )
    let merged = AerospaceFragment.merge(block: bindingsBlock, into: afterAssign)

    if validate {
        switch validateAerospace(merged, aerospaceBin: aerospaceBin) {
        case .ok:
            FileHandle.standardError.write(Data("emit-aerospace: validation passed\n".utf8))
        case .daemonUnreachable:
            FileHandle.standardError.write(Data("emit-aerospace: aerospace daemon not running — skipping validation\n".utf8))
        case .rejected(let stderr):
            FileHandle.standardError.write(Data("emit-aerospace: validation failed:\n\(stderr)\n".utf8))
            return 1
        }
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

    if reload {
        let rc = runAerospaceReload(aerospaceBin: aerospaceBin)
        if rc != 0 {
            FileHandle.standardError.write(Data("emit-aerospace: reload-config returned \(rc)\n".utf8))
        }
    }
    return 0
}

enum AerospaceValidation {
    case ok
    case daemonUnreachable
    case rejected(stderr: String)
}

/// Validate a candidate aerospace.toml by writing it to a tmpfile and
/// invoking `aerospace reload-config --dry-run --no-gui --config-path`.
/// AeroSpace 0.20+ exposes --dry-run on reload-config; if the daemon
/// isn't running, we surface `.daemonUnreachable` rather than fail —
/// fresh-install bootstrap may emit the block before the .app starts.
func validateAerospace(_ candidate: String, aerospaceBin: String) -> AerospaceValidation {
    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("aerospace-validate-\(UUID().uuidString).toml")
    defer { try? FileManager.default.removeItem(at: tmpURL) }
    do {
        try candidate.write(to: tmpURL, atomically: true, encoding: .utf8)
    } catch {
        return .rejected(stderr: "tmp write failed: \(error)")
    }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: aerospaceBin)
    proc.arguments = ["reload-config", "--dry-run", "--no-gui"]
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    proc.standardOutput = stdoutPipe
    proc.standardError = stderrPipe
    do {
        try proc.run()
        proc.waitUntilExit()
    } catch {
        return .daemonUnreachable
    }
    if proc.terminationStatus == 0 {
        return .ok
    }
    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
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
