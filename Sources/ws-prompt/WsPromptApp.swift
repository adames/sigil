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

    /// Worst-case window height: enough for the header, a full
    /// `listMaxHeight` list, and the hint, plus margins. The card is
    /// top-anchored, so when there are fewer rows the extra space just
    /// stays transparent — the window never resizes as rows load.
    private static let windowHeight: CGFloat = 540

    init(mode: PromptMode, service: WorkspaceService) {
        self.mode = mode
        self.service = service
        let pidPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/workspace/ws-prompt.\(mode.rawValue).pid")
        self.pidLock = PIDLock(path: pidPath)

        // Empty + loading: the list is fetched asynchronously in run() so
        // the window paints on the first runloop tick instead of blocking
        // on aerospace.
        let ctl = PromptController(mode: mode, loading: true)
        self.promptController = ctl

        // Small, top-centred window — not a full-screen transparent sheet.
        let screen: NSScreen = NSScreen.main ?? NSScreen.screens.first!
        let cardWidth = PromptStyle.cardWidth(for: screen.frame.width)
        let winWidth = cardWidth + PromptStyle.cardMargin * 2
        let winHeight = Self.windowHeight
        let vis = screen.visibleFrame
        let originX = vis.midX - winWidth / 2
        let originY = vis.maxY - PromptStyle.topInset(for: screen.frame.height) - winHeight
        let win = KeyableWindow(
            contentRect: NSRect(x: originX, y: originY, width: winWidth, height: winHeight),
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

        // Wrap the hosting view in a fixed-frame container so NSHostingView's
        // fitting size can't drive the window's size — the window owns its
        // frame top-down (same guard ws-cheatsheet uses).
        let container = NSView(frame: NSRect(origin: .zero, size: NSSize(width: winWidth, height: winHeight)))
        container.autoresizesSubviews = true
        let hosting = NSHostingView(rootView: PromptView(controller: ctl, cardWidth: cardWidth))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        win.contentView = container

        self.window = win
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

        // Window is up — now fetch the workspace list off the main thread
        // and fill the controller when it lands. Digits typed before it
        // arrives commit optimistically (see PromptController.commitDigit).
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let workspaces = self.service.loadWorkspaces()
            DispatchQueue.main.async { [weak self] in
                self?.promptController.apply(workspaces: workspaces)
            }
        }

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
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53:  return .escape      // kVK_Escape
        case 36:  return .enter       // kVK_Return
        case 48:  return mods.contains(.shift) ? .backTab : .tab
        case 126: return .up          // kVK_UpArrow
        case 125: return .down        // kVK_DownArrow
        default:
            // Any other key resolves to its character; the controller
            // commits on digits and ignores the rest. Arrow/function keys
            // map into U+F700–U+F8FF — drop those so they don't read as
            // digits.
            guard let s = event.charactersIgnoringModifiers, let c = s.first,
                  let scalar = c.unicodeScalars.first,
                  !(0xF700...0xF8FF).contains(scalar.value)
            else { return nil }
            return .char(c)
        }
    }

    private func dispatch(_ key: PromptKey) {
        switch promptController.handle(key) {
        case .idle, .move, .reject:
            // Selection/nudge are @Published — the view re-renders itself.
            return
        case .cancel:
            terminate()
        case .commitSend(let slot):
            service.spawnSend(slot: slot)
            terminate()
        }
    }
}
