import AppKit
import Foundation
import SwiftUI

/// Top-level AppKit + key-dispatch shell for ws-prompt. Owns the
/// borderless overlay window, the NSEvent monitor token, the SIGTERM
/// signal source, the PID-file single-instance lock, and the
/// PromptController for the chosen mode.
///
/// Lifecycle:
///   init(mode:, service:)  → builds controller + window
///   run()                  → blocks on NSApp.run()
///   terminate()            → removes PID file, removes NSEvent
///                            monitor, terminates NSApp
///
/// External dependencies (aerospace, ws, file system) come in through
/// `service` so the App class itself is testable in principle — though
/// the live overlay path is exercised end-to-end via the bash harness.
final class WsPromptApp {
    private let mode: PromptMode
    private let service: WorkspaceService
    private let window: PromptWindow
    private let pidPath: URL

    // Strong refs so the runtime keeps everything alive.
    private let promptController: PromptController
    private var eventMonitorToken: Any?
    private var windowDelegate: WindowDelegate?
    private var signalSource: DispatchSourceSignal?

    init(mode: PromptMode, service: WorkspaceService) {
        self.mode = mode
        self.service = service
        self.pidPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/workspace/ws-prompt.\(mode.rawValue).pid")

        let workspaces = service.loadWorkspaces()

        let screen: NSScreen = NSScreen.main ?? NSScreen.screens.first!
        let win = PromptWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .modalPanel
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        win.isReleasedWhenClosed = false
        self.window = win

        let ctl = PromptController(mode: mode, workspaces: workspaces)
        self.promptController = ctl
        win.contentView = NSHostingView(rootView: PromptView(controller: ctl))
    }

    // MARK: - Lifecycle

    func run() {
        // Single-instance toggle: a second invocation of the same chord
        // dismisses the open instance and exits. Per-mode PID files so a
        // stuck focus prompt doesn't block send.
        if let existing = readExistingPID() {
            kill(existing, SIGTERM)
            exit(0)
        }
        writePID()

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = WindowDelegate { [weak self] in self?.terminate() }
        windowDelegate = delegate
        window.delegate = delegate

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        installKeyMonitor()
        installSignalHandler()

        app.run()
    }

    func terminate() -> Never {
        if let token = eventMonitorToken {
            NSEvent.removeMonitor(token)
            eventMonitorToken = nil
        }
        signalSource?.cancel()
        try? FileManager.default.removeItem(at: pidPath)
        NSApp.terminate(nil)
        exit(0)
    }

    // MARK: - Key dispatch

    /// Local key monitor — runs on the main queue, sees every keyDown
    /// while we're the key window. We swallow the event (return nil) to
    /// keep it from leaking into the foreground app.
    private func installKeyMonitor() {
        eventMonitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard let key = self.decodeKey(event) else { return event }
            self.dispatch(key)
            return nil
        }
    }

    private func decodeKey(_ event: NSEvent) -> PromptKey? {
        switch event.keyCode {
        case 53:  return .escape      // kVK_Escape
        default:
            // Any other key resolves to its character; the controller
            // commits on digits and ignores the rest.
            guard let s = event.charactersIgnoringModifiers, let c = s.first else { return nil }
            return .char(c)
        }
    }

    private func dispatch(_ key: PromptKey) {
        switch promptController.handle(key) {
        case .idle:
            return
        case .cancel:
            terminate()
        case .commitSend(let slot):
            service.spawnSend(slot: slot)
            terminate()
        }
    }

    // MARK: - Signals + PID

    private func installSignalHandler() {
        // SIGTERM from a second `--toggle` invocation: close cleanly.
        // libdispatch handles the signal; ignore the default action.
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in self?.terminate() }
        source.resume()
        signal(SIGTERM, SIG_IGN)
        signalSource = source
    }

    private func readExistingPID() -> Int32? {
        guard let data = try? Data(contentsOf: pidPath),
              let str = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(str), kill(pid, 0) == 0
        else { return nil }
        return pid
    }

    private func writePID() {
        let dir = pidPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "\(getpid())".write(to: pidPath, atomically: true, encoding: .utf8)
    }
}

// MARK: - Helper types

/// NSWindow subclass with `canBecomeKey = true` — required for a
/// borderless window to receive keyDown events.
final class PromptWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Routes window-delegate events (specifically `windowDidResignKey` —
/// blur cancels) back into the App via a closure. Decoupling lets the
/// App own the cancel policy without making it an NSObject subclass.
final class WindowDelegate: NSObject, NSWindowDelegate {
    private let onBlur: () -> Void
    init(onBlur: @escaping () -> Void) { self.onBlur = onBlur }
    func windowDidResignKey(_ notification: Notification) { onBlur() }
}
