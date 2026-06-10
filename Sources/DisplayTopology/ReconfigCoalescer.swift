import CoreGraphics
import Dispatch
import Foundation
import WorkspaceState

/// Coalesces bursts of `CGDisplayRegisterReconfigurationCallback` notifications
/// into a single emission. Apple's docs (and the research) note the callback
/// fires twice for one physical event (begin + post-config); we collect both
/// within a short window and only call the consumer once.
public final class ReconfigCoalescer: @unchecked Sendable {
    public let trailingWindow: TimeInterval
    public let queue: DispatchQueue
    private let onFire: () -> Void

    private var scheduledWorkItem: DispatchWorkItem?
    // NSLock rather than os_unfair_lock: an `os_unfair_lock` stored property
    // passed via `&` may lock a temporary copy (documented-unsafe in Swift).
    private let lock = NSLock()

    public init(
        trailingWindow: TimeInterval = 0.05,
        queue: DispatchQueue = DispatchQueue(label: "\(WorkspaceSystem.bundlePrefix).topology.coalesce"),
        onFire: @escaping () -> Void
    ) {
        self.trailingWindow = trailingWindow
        self.queue = queue
        self.onFire = onFire
    }

    /// Schedule a trailing emission. Repeated calls within the window collapse
    /// into one final invocation.
    public func bump() {
        lock.lock()
        scheduledWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onFire()
        }
        scheduledWorkItem = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + trailingWindow, execute: item)
    }

    /// Cancel any pending emission without firing. Useful for shutdown.
    public func cancel() {
        lock.lock()
        scheduledWorkItem?.cancel()
        scheduledWorkItem = nil
        lock.unlock()
    }
}
