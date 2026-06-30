import AppKit
import Combine
import Foundation
import SwiftUI
import WsUI

// MARK: - Single-instance toggle via PID file
//
// Usage:
//   ws-cheatsheet              → open (or refuse silently if already open)
//   ws-cheatsheet --toggle     → open if closed; close if open
//
// Behavior: writes our PID to ~/.cache/workspace/cheatsheet.pid on open.
// On --toggle, if the pidfile points at a live process, send SIGTERM and
// exit (the running instance handles the signal by closing the window
// and removing the pidfile).

let pidPath = FileManager.default
    .homeDirectoryForCurrentUser
    .appendingPathComponent(".cache/workspace/cheatsheet.pid")

let args = Array(CommandLine.arguments.dropFirst())
let isToggle = args.contains("--toggle")

// MARK: - Offscreen render mode (visual verification)
//
// `ws-cheatsheet --render <width> <height> <out.png>` renders the HUD at a
// simulated visibleFrame size to a PNG and exits — no window, no pidfile,
// nothing shown on screen. Lets the adaptive layout be checked across the
// display matrix (small laptop → large external monitor) without the
// hardware. Mirrors the `--simulate` hooks in ws-prompt / ws-picker.
if let idx = args.firstIndex(of: "--render"), args.count > idx + 3 {
    let w = Double(args[idx + 1]) ?? 1440
    let h = Double(args[idx + 2]) ?? 900
    let out = args[idx + 3]
    let lens = args.count > idx + 4 ? (Int(args[idx + 4]) ?? 0) : 0
    // Top-level code already runs on the main thread; assert that so the
    // main-actor ImageRenderer is reachable from this sync context.
    MainActor.assumeIsolated {
        renderToPNG(size: CGSize(width: w, height: h), lens: lens, to: out)
    }
    exit(0)
}

let pidLock = PIDLock(path: pidPath)

if let existing = pidLock.runningPID() {
    if isToggle {
        // Tell the existing instance to close + clean up.
        kill(existing, SIGTERM)
        exit(0)
    } else {
        // Already open and we're not toggling → silently exit (the user
        // probably bound the hotkey to plain `ws-cheatsheet` and pressed
        // it twice; we don't want a second window stacking up).
        exit(0)
    }
}

pidLock.acquire()

// MARK: - App + window
//
// LSUIElement-equivalent setup at runtime: accessory policy keeps the
// cheatsheet out of the Dock / cmd-tab. We rely on `activate(ignoringOtherApps:)`
// to bring the window forward.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Load the document. If the file is missing, malformed, or has no views
// (an empty `"views": []` decodes fine but leaves nothing to render —
// CheatsheetState.currentLens would trap), show a single error card
// rather than crashing — the user can fix the JSON and reopen.
func errorDocument(reason: String) -> CheatsheetDocument {
    let errorSection = CheatsheetDocument.Section(
        title: "Error",
        rows: [
            ["path", CheatsheetLoader.defaultPath.path],
            ["reason", reason],
        ],
        color: "#ef4444",
        sub: "ws-cheatsheet — load failure"
    )
    return CheatsheetDocument(
        banner: [.init(k: "ERR", v: "cheatsheet.json not usable")],
        views: [
            .init(
                id: "error",
                label: "Error",
                key: "1",
                columns: [.init(sections: ["error"]), .init(sections: []), .init(sections: [])]
            )
        ],
        sections: ["error": errorSection]
    )
}

/// Render the HUD to a PNG at a fixed size, off-screen, then return. Used
/// by `--render` for visual verification. `ImageRenderer` runs a full
/// SwiftUI layout/draw pass without a window, so the real CheatsheetView /
/// SectionCard / layout engine are exercised exactly as on-screen.
@MainActor
func renderToPNG(size: CGSize, lens: Int, to path: String) {
    _ = NSApplication.shared   // realize AppKit for Core Text / font stack
    let loaded = try? CheatsheetLoader.load()
    let document = (loaded.flatMap { $0.views.isEmpty ? nil : $0 })
        ?? errorDocument(reason: "render: cheatsheet.json not usable")
    let state = CheatsheetState(document: document)
    state.currentIndex = max(0, min(lens, document.views.count - 1))
    let content = CheatsheetView(state: state, timestamp: "12:00")
        .frame(width: size.width, height: size.height)

    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    guard let tiff = renderer.nsImage?.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("render: could not produce PNG\n".utf8))
        exit(1)
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
    } catch {
        FileHandle.standardError.write(Data("render: write failed: \(error)\n".utf8))
        exit(1)
    }
}

let document: CheatsheetDocument
do {
    let loaded = try CheatsheetLoader.load()
    document = loaded.views.isEmpty
        ? errorDocument(reason: "\"views\" is empty — the HUD needs at least one view")
        : loaded
} catch {
    document = errorDocument(reason: "\(error)")
}

let state = CheatsheetState(document: document)

let formatter = DateFormatter()
formatter.dateFormat = "HH:mm"
let timestamp = formatter.string(from: Date())

let view = CheatsheetView(state: state, timestamp: timestamp)

// Pick the focused display so the HUD opens where the user is looking.
// Use `visibleFrame` (not `frame`) so the window sits below the macOS
// menu bar and above the Dock — otherwise the banner card clips under
// the menu strip on its top edge.
let screen: NSScreen = NSScreen.main ?? NSScreen.screens.first!
let frame = screen.visibleFrame

// Borderless overlay. KeyableWindow forces key/main so keyDown reaches
// the local monitor; staying out of the Dock / cmd-tab comes from the
// `.accessory` activation policy above, not the style mask.
let window = CheatsheetWindow(
    contentRect: frame,
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)

window.isOpaque = false
window.backgroundColor = NSColor.clear
window.hasShadow = false
window.level = NSWindow.Level.modalPanel
window.collectionBehavior = [.canJoinAllSpaces, NSWindow.CollectionBehavior.fullScreenAuxiliary]
window.isReleasedWhenClosed = false
window.hidesOnDeactivate = false

// CRITICAL: NSHostingView reports the SwiftUI view's `fittingSize` as its
// intrinsic content size, and the host window auto-resizes to fit. With
// CheatsheetView using `.frame(maxHeight: .infinity)` and stacks of cards,
// the propagated fitting height is ~14636 px — the window grows off-screen
// within one runloop tick of being shown, which is what the user sees as
// "disappeared after 1-2 seconds". Wrap the hosting view in a plain
// NSView with a fixed frame to absorb the resize signal.
let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
container.autoresizesSubviews = true
let hosting = NSHostingView(rootView: view)
hosting.frame = container.bounds
hosting.autoresizingMask = [.width, .height]
container.addSubview(hosting)
window.contentView = container

// Lock the window's frame: even if something else tries to resize us
// (AeroSpace's tiling pass, AppKit auto-layout, errant SwiftUI passes),
// `setFrame` snaps back to the screen rect. See CheatsheetWindow.lockedFrame below.
let screenFrame = frame
window.setFrame(screenFrame, display: true)
window.contentMinSize = screenFrame.size
window.contentMaxSize = screenFrame.size

// Arm the frame lock — from now on, every setFrame call is clamped to
// the screen frame.
window.lockedFrame = screenFrame

// Show window and activate
window.makeKeyAndOrderFront(nil as NSResponder?)
NSApp.activate(ignoringOtherApps: true)
window.makeKeyAndOrderFront(nil as NSResponder?)

// MARK: - Keyboard input
//
// Local event monitor catches keyDown while the HUD is the key window:
//   - Number keys 1..N → jump to the matching lens
//   - Tab / Shift-Tab  → cycle through lenses
//   - Esc              → close (same path as SIGTERM)
// Other keys pass through unchanged (returning the event lets the system
// beep convention apply, but for borderless HUD windows nothing else
// listens — the practical effect is that other keys do nothing).

let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    // Esc — keyCode 53.
    if event.keyCode == 53 {
        terminate()
    }
    // Tab — keyCode 48. Shift-Tab goes backwards.
    if event.keyCode == 48 {
        if event.modifierFlags.contains(.shift) {
            state.previousLens()
        } else {
            state.nextLens()
        }
        return nil
    }
    // Lens jump by key character (digits 1..9, or any single char
    // matching a lens's `key` field).
    if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
        if state.selectLens(byKey: chars) {
            return nil
        }
    }
    return event
}
_ = keyMonitor

// MARK: - Dismissal: SIGTERM (via Hyper key toggle) or Esc
//
// Caps+/ (Hyper key) runs `ws-cheatsheet --toggle` which sends SIGTERM
// to this process. Inside the HUD, Esc terminates directly via the key
// monitor above.

class AppController: NSObject, NSWindowDelegate, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
let controller = AppController()
window.delegate = controller
NSApp.delegate = controller

// SIGTERM closes us cleanly (sent by toggle).
let termSource = installSignalHandler(SIGTERM) {
    terminate()
}
// Keep the dispatch source alive for the lifetime of the process.
_ = termSource

func terminate() -> Never {
    pidLock.release()
    NSApp.terminate(nil)
    exit(0)
}

// Cleanup guard: if the process dies via a path that skips `terminate()`
// (SIGINT etc.), remove the pidfile so the next invocation sees a clean
// state. `atexit` takes a C function pointer that can't capture context,
// but `pidLock` is file-scope, so referencing it here is not a capture.
atexit {
    pidLock.release()
}

app.run()

// MARK: - CheatsheetWindow
//
// KeyableWindow that also clamps every external setFrame back to the
// screen rect — NSHostingView auto-sizing / AeroSpace / errant SwiftUI
// passes can otherwise push the HUD off-screen (see lockedFrame).
final class CheatsheetWindow: KeyableWindow {
    /// When non-nil, all `setFrame` calls are clamped to this rect. We arm
    /// it after the window is shown so the initial layout still works but
    /// later resize requests (from NSHostingView auto-sizing, AeroSpace,
    /// etc.) can't push the content off-screen.
    var lockedFrame: NSRect?

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        if let locked = lockedFrame {
            super.setFrame(locked, display: flag)
        } else {
            super.setFrame(frameRect, display: flag)
        }
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        if let locked = lockedFrame {
            super.setFrame(locked, display: displayFlag, animate: false)
        } else {
            super.setFrame(frameRect, display: displayFlag, animate: animateFlag)
        }
    }
}

// MARK: - CheatsheetState (observable)
//
// Holds the loaded document + the current lens index. Mutating
// `currentIndex` triggers a SwiftUI rerender of CheatsheetView via the
// @ObservedObject binding.

final class CheatsheetState: ObservableObject {
    let document: CheatsheetDocument
    @Published var currentIndex: Int = 0

    init(document: CheatsheetDocument) {
        self.document = document
    }

    var currentLens: CheatsheetDocument.Lens {
        document.views[currentIndex]
    }

    /// Jump to the lens whose `key` matches the given character(s).
    /// Returns true on a match so the caller can consume the event.
    @discardableResult
    func selectLens(byKey key: String) -> Bool {
        guard let idx = document.views.firstIndex(where: { $0.key == key }) else {
            return false
        }
        if idx != currentIndex {
            currentIndex = idx
        }
        return true
    }

    func nextLens() {
        guard !document.views.isEmpty else { return }
        currentIndex = (currentIndex + 1) % document.views.count
    }

    func previousLens() {
        guard !document.views.isEmpty else { return }
        currentIndex = (currentIndex - 1 + document.views.count) % document.views.count
    }
}
