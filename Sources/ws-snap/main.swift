import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - ws-snap
//
// Absolute window snaps for aerospace-unmanaged windows (floating windows
// like System Settings, or Ghostty when a tile rule excludes it).
// Not bound to a chord today — the common new-window case is handled
// by configs/workspace/stage-window.sh from aerospace's window_created
// signal. ws-snap remains as a manual CLI for one-off absolute snaps.
//
// We use the Accessibility API directly because aerospace's CLI only
// affects managed windows, and we explicitly want to move floating
// ones.
//
// Usage:
//   ws-snap left | right | max | center
//
// Geometry fractions apply to the screen's visible frame (menu bar and
// Dock excluded), matching the previous Lua version's screen:frame() so
// the muscle memory carries over.

enum SnapRegion: String {
    case left, right, max, center

    /// Fraction of the target screen's visible frame: (x, y, w, h) in [0, 1].
    var fraction: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        switch self {
        case .left:   return (0,    0,    0.5, 1)
        case .right:  return (0.5,  0,    0.5, 1)
        case .max:    return (0,    0,    1,   1)
        case .center: return (0.25, 0.25, 0.5, 0.5)
        }
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let first = args.first, let region = SnapRegion(rawValue: first) else {
    FileHandle.standardError.write(Data("usage: ws-snap <left|right|max|center>\n".utf8))
    exit(2)
}

// On success, flash a brief ghost rectangle over the snap target so the
// move is confirmed visually (the rest of Sigil is overlay-driven; a
// silent CLI snap was the odd one out). Scripts can opt out with
// WS_SNAP_NO_FLASH=1.
guard let target = snap(region) else { exit(1) }
if ProcessInfo.processInfo.environment["WS_SNAP_NO_FLASH"] == "1" {
    exit(0)
}
flashConfirmation(in: target)   // runs an NSApp loop, then exit(0)

// MARK: - Snap

/// Move the focused floating window to `region`. Returns the target rect
/// (AppKit coords) on success so the caller can flash it, or nil on any
/// failure.
func snap(_ region: SnapRegion) -> NSRect? {
    guard let window = focusedWindow() else {
        FileHandle.standardError.write(Data("ws-snap: no focused window\n".utf8))
        return nil
    }
    guard let screen = screenForWindow(window) else {
        FileHandle.standardError.write(Data("ws-snap: cannot resolve screen for focused window\n".utf8))
        return nil
    }

    let f = region.fraction
    let s = screen.visibleFrame

    // AppKit visibleFrame is in AppKit coords (origin bottom-left of
    // primary). AX expects CG coords (origin top-left of primary). We
    // convert once for the rect we're about to write.
    let target = NSRect(
        x: s.origin.x + s.size.width  * f.x,
        y: s.origin.y + s.size.height * f.y,
        width:  s.size.width  * f.w,
        height: s.size.height * f.h
    )
    let cgTarget = appKitRectToCG(target)

    var position = CGPoint(x: cgTarget.origin.x, y: cgTarget.origin.y)
    var size     = CGSize(width: cgTarget.size.width, height: cgTarget.size.height)

    guard let posValue = AXValueCreate(.cgPoint, &position),
          let sizeValue = AXValueCreate(.cgSize, &size) else {
        FileHandle.standardError.write(Data("ws-snap: AXValueCreate failed\n".utf8))
        return nil
    }

    let posResult  = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
    let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

    if posResult != .success || sizeResult != .success {
        FileHandle.standardError.write(
            Data("ws-snap: AX set failed (pos=\(posResult.rawValue) size=\(sizeResult.rawValue))\n".utf8)
        )
        return nil
    }
    return target
}

// MARK: - Confirmation flash
//
// A momentary borderless ghost rectangle at the snap target: fade in,
// hold, fade out, exit. Pure AppKit (no SwiftUI/WsUI dep) and never
// activates or takes mouse events, so the snapped window keeps focus.
// Accent is Catppuccin blue — a fixed hue is fine for a 0.4s flash.

func flashConfirmation(in rect: NSRect) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let win = NSWindow(
        contentRect: rect,
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    win.isOpaque = false
    win.backgroundColor = .clear
    win.hasShadow = false
    win.level = .modalPanel
    win.ignoresMouseEvents = true
    win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

    let accent = NSColor(srgbRed: 0x89 / 255, green: 0xb4 / 255, blue: 0xfa / 255, alpha: 1)
    let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
    view.wantsLayer = true
    if let layer = view.layer {
        layer.cornerRadius = 10
        layer.borderWidth = 2
        layer.borderColor = accent.cgColor
        layer.backgroundColor = accent.withAlphaComponent(0.12).cgColor
    }
    win.contentView = view

    win.alphaValue = 0
    win.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.12
        win.animator().alphaValue = 1
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            win.animator().alphaValue = 0
        }, completionHandler: { exit(0) })
    }
    app.run()
}

// MARK: - AX helpers

func focusedWindow() -> AXUIElement? {
    let systemWide = AXUIElementCreateSystemWide()
    var appRef: AnyObject?
    let appStatus = AXUIElementCopyAttributeValue(
        systemWide,
        kAXFocusedApplicationAttribute as CFString,
        &appRef
    )
    guard appStatus == .success, let appElement = appRef else { return nil }

    var windowRef: AnyObject?
    let winStatus = AXUIElementCopyAttributeValue(
        // swiftlint:disable:next force_cast
        appElement as! AXUIElement,
        kAXFocusedWindowAttribute as CFString,
        &windowRef
    )
    guard winStatus == .success, let win = windowRef else { return nil }
    // swiftlint:disable:next force_cast
    return (win as! AXUIElement)
}

// MARK: - Screen resolution

func screenForWindow(_ window: AXUIElement) -> NSScreen? {
    // Use the window's current top-left to pick a screen — matches the
    // user's expectation that the snap stays on the display the window
    // is already on. Falls back to NSScreen.main on read failure.
    //
    // The hit test stays in CG coordinates against CGDisplayBounds: flipped
    // to AppKit, a window flush with a screen's top edge lands exactly on
    // frame.maxY, which NSRect.contains excludes — the lookup would fall
    // through to the wrong screen. In CG coords that same point is the
    // bounds' minY, which is included.
    var posRef: AnyObject?
    if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
       let raw = posRef {
        // swiftlint:disable:next force_cast
        let value = raw as! AXValue
        var point = CGPoint.zero
        if AXValueGetValue(value, .cgPoint, &point) {
            for s in NSScreen.screens {
                guard let id = displayID(for: s) else { continue }
                if CGDisplayBounds(id).contains(point) {
                    return s
                }
            }
        }
    }
    return NSScreen.main
}

func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    guard let raw = screen.deviceDescription[key] as? NSNumber else { return nil }
    return CGDirectDisplayID(raw.uint32Value)
}

// MARK: - Coordinate conversion
//
// CG origin = top-left of primary screen, y grows down.
// AppKit origin = bottom-left of primary screen, y grows up.
// We flip across the primary screen's frame.maxY.

func appKitRectToCG(_ rect: NSRect) -> CGRect {
    guard let primary = NSScreen.screens.first else { return rect }
    let flippedY = primary.frame.maxY - rect.origin.y - rect.size.height
    return CGRect(x: rect.origin.x, y: flippedY, width: rect.size.width, height: rect.size.height)
}
