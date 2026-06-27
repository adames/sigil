import AppKit
import Foundation
import SwiftUI
import WsUI

/// AppKit shell for ws-picker. Mirrors ws-prompt's WsPromptApp:
///   - Borderless modalPanel overlay that joins all spaces
///   - Local NSEvent monitor that swallows keyDown so chords don't leak
///   - SIGTERM handler for the second-invocation toggle
///   - PID-file single-instance lock under ~/.cache/workspace/
///   - windowDidResignKey blur dismissal
///
/// External dependencies (aerospace) come in via WindowSource so the App
/// is in principle testable; nothing automated drives the live overlay
/// path today — `--simulate-keys` exists for manual smoke-testing.
final class WsPickerApp {
    private let source: WindowSource
    private let window: KeyableWindow
    private let controller: PickerController
    private let pidLock: PIDLock

    private var eventMonitorToken: Any?
    private var windowDelegate: BlurDismissDelegate?
    private var signalSource: DispatchSourceSignal?

    /// Worst-case window height: header + query field + a full
    /// `listMaxHeight` list + hint, plus margins. The card is top-anchored,
    /// so fewer rows just leave transparent space — no window resize.
    private static let windowHeight: CGFloat = 580

    init(source: WindowSource) {
        self.source = source
        let pidPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/workspace/ws-picker.pid")
        self.pidLock = PIDLock(path: pidPath)

        // Empty + loading: the window list is fetched asynchronously in
        // run() so the overlay paints without blocking on aerospace.
        let ctl = PickerController(loading: true)
        self.controller = ctl

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

        // Fixed-frame container so NSHostingView's fitting size can't drive
        // the window size — the window owns its frame top-down.
        let container = NSView(frame: NSRect(origin: .zero, size: NSSize(width: winWidth, height: winHeight)))
        container.autoresizesSubviews = true
        let hosting = NSHostingView(rootView: PickerView(controller: ctl, cardWidth: cardWidth))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        win.contentView = container

        self.window = win
    }

    // MARK: - Lifecycle

    func run() {
        // Single-instance toggle: a second Caps+c while the picker is
        // open closes it. Same pattern as ws-prompt — one PID file
        // distinct from any prompt PID file so the two overlays don't
        // collide.
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

        // Window is up — fetch the window list off the main thread and fill
        // the controller when it lands. Typing filters as soon as it does.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let items = self.source.loadWindows()
            DispatchQueue.main.async { [weak self] in
                self?.controller.apply(items: items)
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

    private func installKeyMonitor() {
        eventMonitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard let key = self.decodeKey(event) else { return event }
            self.dispatch(key)
            return nil
        }
    }

    private func decodeKey(_ event: NSEvent) -> PickerKey? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53:  return .escape
        case 36:  return .enter
        case 48:  return mods.contains(.shift) ? .backTab : .tab
        case 51:  return .backspace
        default:
            guard let s = event.charactersIgnoringModifiers, let c = s.first else { return nil }
            // Arrow / function / navigation keys map into the Unicode
            // function-key range (U+F700–U+F8FF); appending those to the
            // fuzzy query silently empties the match list.
            guard let scalar = c.unicodeScalars.first,
                  !(0xF700...0xF8FF).contains(scalar.value) else { return nil }
            return .char(c)
        }
    }

    private func dispatch(_ key: PickerKey) {
        switch controller.handle(key) {
        case .idle, .refilter:    return
        case .cancel:             terminate()
        case .commit(let id):
            source.focus(windowID: id)
            terminate()
        }
    }
}
