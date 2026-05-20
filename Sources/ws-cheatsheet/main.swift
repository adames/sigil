import AppKit
import Foundation
import SwiftUI

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

func readExistingPID() -> Int32? {
    guard let data = try? Data(contentsOf: pidPath),
          let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          let pid = Int32(str) else { return nil }
    // kill(pid, 0) returns 0 if the process exists, -1 otherwise.
    if kill(pid, 0) == 0 { return pid }
    return nil
}

func writePID() {
    let dir = pidPath.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? "\(getpid())".write(to: pidPath, atomically: true, encoding: .utf8)
}

func removePID() {
    try? FileManager.default.removeItem(at: pidPath)
}

if let existing = readExistingPID() {
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

writePID()

// MARK: - App + window
//
// LSUIElement-equivalent setup at runtime: accessory policy keeps the
// cheatsheet out of the Dock / cmd-tab. We rely on `activate(ignoringOtherApps:)`
// to bring the window forward.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Load the document. If the file is missing or malformed, show a single
// error card rather than crashing — the user can fix the JSON and reopen.
let document: CheatsheetDocument
do {
    document = try CheatsheetLoader.load()
} catch {
    let errorSection = CheatsheetDocument.Section(
        title: "Error",
        rows: [
            ["path", CheatsheetLoader.defaultPath.path],
            ["reason", "\(error)"],
        ],
        color: "#ef4444",
        sub: "ws-cheatsheet — load failure"
    )
    document = CheatsheetDocument(
        banner: [.init(k: "ERR", v: "cheatsheet.json not loadable")],
        columns: [.init(sections: [errorSection])]
    )
}

let formatter = DateFormatter()
formatter.dateFormat = "HH:mm"
let timestamp = formatter.string(from: Date())

let view = CheatsheetView(document: document, timestamp: timestamp)

// Pick the focused display so the HUD opens where the user is looking.
let screen: NSScreen = NSScreen.main ?? NSScreen.screens.first!
let frame = screen.frame

// Use .nonactivatingPanel to stay out of Dock but still become key
let window = CheatsheetWindow(
    contentRect: frame,
    styleMask: [.borderless, .nonactivatingPanel],
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

// MARK: - Dismissal: SIGTERM only (via Hyper key toggle)
//
// The ONLY way to close the cheatsheet is pressing Caps+; (Hyper key),
// which runs `ws-cheatsheet --toggle` and sends SIGTERM to this process.
// No Esc, no focus loss dismissal, no clicking elsewhere.

class AppController: NSObject, NSWindowDelegate, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
let controller = AppController()
window.delegate = controller
NSApp.delegate = controller

// SIGTERM closes us cleanly (sent by toggle).
func installSignalHandler(_ sig: Int32, action: @escaping () -> Void) -> DispatchSourceSignal {
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler(handler: action)
    src.resume()
    signal(sig, SIG_IGN)
    return src
}

let termSource = installSignalHandler(SIGTERM) {
    terminate()
}
// Keep the dispatch source alive for the lifetime of the process.
_ = termSource

func terminate() -> Never {
    removePID()
    NSApp.terminate(nil)
    exit(0)
}

// CleanUp guard: if the process gets killed via SIGINT etc, remove the
// pidfile so the next invocation sees a clean state.
atexit {
    try? FileManager.default.removeItem(
        at: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/workspace/cheatsheet.pid")
    )
}

app.run()

// MARK: - NSWindow subclass that can become key (required for keyDown delivery
// to a borderless window) and refuses external resize attempts.
final class CheatsheetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

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
