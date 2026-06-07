import Foundation

// ws-prompt send [--simulate-keys "<keys>"]
//
// The runtime is split across:
//
//   PromptController  — send (follow) state machine (pure-ish; ObservableObject)
//   WorkspaceService  — single seam to aerospace / ws CLI / file system
//   WsPromptApp       — AppKit window + key dispatch + lifecycle
//   PromptView        — SwiftUI rendering bound to the controller
//
// This file just parses argv, picks production vs. simulate path, and
// hands off. `send` is the only mode — the old `focus`/"go" prompt was
// removed (AeroSpace's Caps+1…0 covers workspace focus).

let rawArgs = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    FileHandle.standardError.write(Data(
        "usage: ws-prompt <send> [--simulate-keys \"<keys>\"]\n".utf8))
    exit(2)
}

guard let modeArg = rawArgs.first, let mode = PromptMode(rawValue: modeArg) else { usage() }

// Optional --simulate-keys "<keys>" → headless smoke harness for the
// send state machine.
if let i = rawArgs.firstIndex(of: "--simulate-keys"), i + 1 < rawArgs.count {
    let keys = rawArgs[i + 1]
    let service = ProductionWorkspaceService()
    let controller = PromptController(mode: mode, workspaces: service.loadWorkspaces())
    let result = controller.simulate(KeySequenceParser.parse(keys))
    exit(SimulateReporter.print(action: result, mode: mode))
}

// Live mode: build the App and run its NSApp loop. The App handles
// PID-file single-instance, NSEvent monitoring, SIGTERM, and the
// terminate path.
let app = WsPromptApp(mode: mode, service: ProductionWorkspaceService())
app.run()
