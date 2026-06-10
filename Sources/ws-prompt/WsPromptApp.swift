import AppKit
import Foundation
import SwiftUI
import WsUI

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
/// `service` so the App class itself is testable in principle; nothing
/// automated drives the live overlay path today — `--simulate-keys`
/// exists for manual smoke-testing.
final class WsPromptApp {
    private let mode: PromptMode
    private let service: WorkspaceService
    private let window: KeyableWindow
    private let pidLock: PIDLock

    // Strong refs so the runtime keeps everything alive.
    private let promptController: PromptController
    private var eventMonitorToken: Any?
    private var windowDelegate: BlurDismissDelegate?
    private var signalSource: DispatchSourceSignal?

    init(mode: PromptMode, service: WorkspaceService) {
        self.mode = mode
        self.service = service
        let pidPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/workspace/ws-prompt.\(mode.rawValue).pid")
        self.pidLock = PIDLock(path: pidPath)

        let workspaces = service.loadWorkspaces()

        let screen: NSScreen = NSScreen.main ?? NSScreen.screens.first!
        let win = KeyableWindow(
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
        if let existing = pidLock.runningPID() {
            kill(existing, SIGTERM)
            exit(0)
        }
        pidLock.acquire()

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = BlurDismissDelegate { [weak self] in self?.terminate() }
        windowDelegate = delegate
        window.delegate = delegate

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        installKeyMonitor()
        signalSource = installSignalHandler(SIGTERM) { [weak self] in self?.terminate() }

        app.run()
    }

    func terminate() -> Never {
        if let token = eventMonitorToken {
            NSEvent.removeMonitor(token)
            eventMonitorToken = nil
        }
        signalSource?.cancel()
        pidLock.release()
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
}
