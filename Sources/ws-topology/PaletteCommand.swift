import DisplayTopology
import Foundation
import PaletteCore

// MARK: - resolve-palette
//
// Derive Sigil's base palette from the user's terminal (Ghostty for now)
// and write ~/.config/workspace/palette.json. The Swift side owns the
// color math + JSON; `cli/ws palette` is a thin wrapper. Non-fatal by
// design: if Ghostty isn't found or the theme is unreadable, we leave
// Sigil on its compiled-in Catppuccin fallback and say so.

func cmdResolvePalette(args: [String]) -> Int32 {
    var write = false
    var force = false
    var ghosttyOverride: String?
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--write": write = true
        case "--force": force = true
        case "--ghostty":
            if i + 1 < args.count { ghosttyOverride = args[i + 1]; i += 1 }
        case "-h", "--help":
            printPaletteUsage()
            return 0
        default:
            FileHandle.standardError.write(Data("resolve-palette: unknown flag: \(args[i])\n".utf8))
            printPaletteUsage()
            return 2
        }
        i += 1
    }

    // An explicit --ghostty PATH is authoritative: if it isn't a runnable
    // binary, fail loudly rather than silently autodetecting a different
    // one (the caller asked for this specific binary).
    if let override = ghosttyOverride,
       !FileManager.default.isExecutableFile(atPath: override) {
        FileHandle.standardError.write(Data(
            "resolve-palette: --ghostty \(override) is not an executable file.\n".utf8))
        return 2
    }

    // Locate the Ghostty binary (it isn't on PATH by default).
    guard let ghostty = GhosttyLocator.find(override: ghosttyOverride) else {
        FileHandle.standardError.write(Data(
            "resolve-palette: ghostty not found (looked at $GHOSTTY_BIN, PATH, /Applications/Ghostty.app). Leaving Sigil on the Catppuccin fallback.\n".utf8))
        return 0   // non-fatal: install.sh keeps going
    }

    let configText: String
    do {
        configText = try GhosttyLocator.showConfig(binary: ghostty)
    } catch {
        FileHandle.standardError.write(Data("resolve-palette: ghostty +show-config failed: \(error). Leaving fallback in place.\n".utf8))
        return 0
    }

    let parsed = GhosttyPalette.parse(configText)

    let document: PaletteDocument
    do {
        document = try PaletteResolver.resolve(from: parsed, source: "ghostty")
    } catch PaletteResolver.Failure.missingSurfaces {
        FileHandle.standardError.write(Data("resolve-palette: terminal config had no background/foreground. Leaving fallback in place.\n".utf8))
        return 0
    } catch PaletteResolver.Failure.lowContrast(let ratio) {
        FileHandle.standardError.write(Data(String(format:
            "resolve-palette: terminal fg/bg contrast %.2f below %.1f floor — would be unreadable. Leaving fallback in place.\n",
            ratio, PaletteResolver.minContrast).utf8))
        return 0
    } catch {
        FileHandle.standardError.write(Data("resolve-palette: \(error)\n".utf8))
        return 1
    }

    let json: String
    do {
        json = try CacheEncoding.encode(document)
    } catch {
        FileHandle.standardError.write(Data("resolve-palette: encode failed: \(error)\n".utf8))
        return 1
    }

    guard write else {
        // Dry run: emit to stdout for inspection / `ws palette show`.
        print(json)
        return 0
    }

    let target = paletteOutputURL()

    // Respect a manual lock: a hand-authored palette.json with
    // "source":"manual" is never clobbered by sync without --force.
    if !force, let existing = try? Data(contentsOf: target),
       let prior = try? JSONDecoder().decode(PaletteDocument.self, from: existing),
       prior.source == "manual" {
        FileHandle.standardError.write(Data(
            "resolve-palette: \(target.path) is marked \"source\":\"manual\"; refusing to overwrite (pass --force).\n".utf8))
        return 0
    }

    do {
        try CacheEncoding.atomicWrite(json, to: target)
    } catch {
        FileHandle.standardError.write(Data("resolve-palette: write failed: \(error)\n".utf8))
        return 1
    }
    FileHandle.standardError.write(Data("resolve-palette: wrote \(target.path) (source: ghostty)\n".utf8))
    return 0
}

/// Destination for palette.json. `WS_PALETTE` overrides (kept in sync
/// with the DesignSystem loader); otherwise the workspace config dir.
func paletteOutputURL() -> URL {
    let env = ProcessInfo.processInfo.environment
    if let override = env["WS_PALETTE"], !override.isEmpty {
        return URL(fileURLWithPath: override)
    }
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".config/workspace/palette.json")
}

func printPaletteUsage() {
    let usage = """
    usage: ws-topology resolve-palette [--write] [--force] [--ghostty PATH]

      Derive Sigil's palette from the terminal and print it (dry-run) or
      write ~/.config/workspace/palette.json (--write).

      --write          write palette.json (default: print to stdout)
      --force          overwrite even a "source":"manual" palette.json
      --ghostty PATH   use this ghostty binary instead of autodetecting

    Ghostty binary resolution order: $GHOSTTY_BIN, `command -v ghostty`,
    /Applications/Ghostty.app/Contents/MacOS/ghostty. If none is found the
    command is a no-op and Sigil keeps its built-in Catppuccin palette.

    """
    FileHandle.standardError.write(Data(usage.utf8))
}

// MARK: - Ghostty binary discovery

enum GhosttyLocator {
    static func find(override: String? = nil) -> String? {
        let fm = FileManager.default
        if let override, fm.isExecutableFile(atPath: override) { return override }

        if let env = ProcessInfo.processInfo.environment["GHOSTTY_BIN"],
           !env.isEmpty, fm.isExecutableFile(atPath: env) {
            return env
        }
        if let onPath = which("ghostty") { return onPath }

        let app = "/Applications/Ghostty.app/Contents/MacOS/ghostty"
        if fm.isExecutableFile(atPath: app) { return app }
        return nil
    }

    /// `command -v ghostty` equivalent.
    private static func which(_ name: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["which", name]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch { return nil }
        guard proc.terminationStatus == 0 else { return nil }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    /// Run `ghostty +show-config --default=true` and return its stdout.
    static func showConfig(binary: String) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = ["+show-config", "--default=true"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
