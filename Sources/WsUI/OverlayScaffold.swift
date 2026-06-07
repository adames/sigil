import AppKit
import Foundation

// MARK: - Overlay app scaffolding
//
// The single-instance, borderless-overlay lifecycle shared by every sigil
// overlay (ws-prompt, ws-picker, ws-cheatsheet). Each used to carry its own
// byte-identical copy of these four pieces; hoisted here so the lifecycle
// has one home. UX (chords, blur-to-dismiss, the second-invocation toggle)
// is unchanged — only the duplication is gone.

/// Borderless overlay window. A borderless `NSWindow` refuses to become key
/// by default, so it never sees keyDown; forcing both flags fixes that.
/// `open` so ws-cheatsheet can subclass to add its frame lock.
open class KeyableWindow: NSWindow {
    open override var canBecomeKey: Bool { true }
    open override var canBecomeMain: Bool { true }
}

/// Forwards `windowDidResignKey` (blur) to a closure so the owning App can
/// keep its cancel policy without being an `NSObject` subclass itself.
public final class BlurDismissDelegate: NSObject, NSWindowDelegate {
    private let onBlur: () -> Void
    public init(onBlur: @escaping () -> Void) { self.onBlur = onBlur }
    public func windowDidResignKey(_ notification: Notification) { onBlur() }
}

/// PID-file lock behind the single-instance toggle: a second invocation of
/// the same chord finds the live PID, SIGTERMs it, and exits. Path is the
/// caller's so each overlay keeps its own distinct pidfile under
/// ~/.cache/workspace/.
public struct PIDLock {
    public let path: URL
    public init(path: URL) { self.path = path }

    /// PID currently holding the lock, or nil if the file is absent or
    /// points at a dead process (`kill(pid, 0)` probes liveness).
    public func runningPID() -> Int32? {
        guard let data = try? Data(contentsOf: path),
              let str = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(str), kill(pid, 0) == 0
        else { return nil }
        return pid
    }

    public func acquire() {
        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? "\(getpid())".write(to: path, atomically: true, encoding: .utf8)
    }

    public func release() {
        try? FileManager.default.removeItem(at: path)
    }
}

/// Install a signal handler on `queue` and return the source (the caller
/// must retain it). libdispatch handles delivery; the default disposition
/// is ignored so the process doesn't die before the handler runs.
@discardableResult
public func installSignalHandler(
    _ signalNumber: Int32,
    queue: DispatchQueue = .main,
    action: @escaping () -> Void
) -> DispatchSourceSignal {
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: queue)
    source.setEventHandler(handler: action)
    source.resume()
    signal(signalNumber, SIG_IGN)
    return source
}
