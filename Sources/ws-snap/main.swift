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

exit(snap(region) ? 0 : 1)

// MARK: - Snap

func snap(_ region: SnapRegion) -> Bool {
    guard let window = focusedWindow() else {
        FileHandle.standardError.write(Data("ws-snap: no focused window\n".utf8))
        return false
    }
    guard let screen = screenForWindow(window) else {
        FileHandle.standardError.write(Data("ws-snap: cannot resolve screen for focused window\n".utf8))
        return false
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
        return false
    }

    let posResult  = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
    let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

    if posResult != .success || sizeResult != .success {
        FileHandle.standardError.write(
            Data("ws-snap: AX set failed (pos=\(posResult.rawValue) size=\(sizeResult.rawValue))\n".utf8)
        )
        return false
    }
    return true
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
