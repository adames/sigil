import AdaptersAppKit
import AppKit
import CoreGraphics
import DisplayTopology
import Foundation
import LayoutPolicy
import OSLog
import WorkspaceState

// The daemon needs NSScreen access, which requires a WindowServer connection.
// The `.accessory` activation policy keeps the process out of the Dock and
// command-tab. (A bare launchd binary has no app bundle, so there is no
// Info.plist for `LSUIElement` to live in; the activation policy alone does
// the work.)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let daemon = TopologyDaemon()
daemon.start()

app.run()

final class TopologyDaemon: @unchecked Sendable {
    let cacheDir: URL
    // The coalescer invokes `onFire` on the queue it is given. It must be the
    // main queue here: `publish()` uses `MainActor.assumeIsolated` (NSScreen is
    // main-thread-only), which traps — SIGTRAP, masked by launchd's KeepAlive
    // as a crash-loop — if the fire path runs anywhere else.
    private lazy var coalescer: ReconfigCoalescer = ReconfigCoalescer(queue: .main) { [weak self] in
        self?.publish()
    }
    // Dedupe state for the published files. Snapshot/policies are stored with
    // `capturedAt` normalized so the comparison tracks topology facts, not the
    // wall clock (a raw JSON compare would differ on every capture).
    private var lastSnapshot: TopologySnapshot?
    private var lastPolicies: LayoutPolicySet?
    private var lastAccessibility: AccessibilityState?
    private var lastLayoutEnv: String?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.cacheDir = home.appendingPathComponent(".cache/workspace")
    }

    func start() {
        TopologyLog.topology.info("ws-topologyd starting; cache dir=\(self.cacheDir.path, privacy: .public)")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        registerCGCallback()
        registerAppKitNotifications()
        publish()
    }

    private func registerCGCallback() {
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        let status = CGDisplayRegisterReconfigurationCallback({ (_, _, userInfo) in
            guard let userInfo else { return }
            let daemon = Unmanaged<TopologyDaemon>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                daemon.coalescer.bump()
            }
        }, opaque)
        if status != .success {
            TopologyLog.topology.error("CGDisplayRegisterReconfigurationCallback failed: \(String(describing: status), privacy: .public)")
        }
    }

    private func registerAppKitNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.coalescer.bump()
        }
    }

    private func publish() {
        MainActor.assumeIsolated {
            self.publishOnMain()
        }
    }

    @MainActor
    private func publishOnMain() {
        let snapshot = DisplayTopologyService.snapshot()
        let access   = AccessibilityProbe.current()
        let policies = LayoutPolicyEngine.policies(
            for: snapshot.displays,
            reduceMotion: access.reduceMotion,
            increaseContrast: access.increaseContrast
        )

        var didRewriteFile = false

        // Compare with capturedAt pinned to a sentinel; the written JSON keeps
        // the real timestamps. nil last-values force the initial publish.
        var comparableSnapshot = snapshot
        comparableSnapshot.capturedAt = .distantPast
        var comparablePolicies = policies
        comparablePolicies.capturedAt = .distantPast

        if comparableSnapshot != lastSnapshot
            || comparablePolicies != lastPolicies
            || access != lastAccessibility {
            do {
                let json = try CacheEncoding.encode(EnrichedTopology(
                    topology: snapshot,
                    policies: policies,
                    accessibility: access
                ))
                try CacheEncoding.atomicWrite(
                    json,
                    to: cacheDir.appendingPathComponent("topology.json")
                )
                lastSnapshot = comparableSnapshot
                lastPolicies = comparablePolicies
                lastAccessibility = access
                didRewriteFile = true
                TopologyLog.topology.info("topology.json updated: \(snapshot.displays.count, privacy: .public) display(s)")
                logDiff(snapshot: snapshot, policies: policies)
            } catch {
                TopologyLog.topology.error("topology.json encode failed: \(String(describing: error), privacy: .public)")
            }
        }

        let env = LayoutEnvRenderer.render(
            snapshot: snapshot,
            policies: policies,
            accessibility: access
        )
        if env != lastLayoutEnv {
            do {
                try CacheEncoding.atomicWrite(
                    env,
                    to: cacheDir.appendingPathComponent("layout.env")
                )
                lastLayoutEnv = env
                didRewriteFile = true
            } catch {
                TopologyLog.topology.error("layout.env write failed: \(String(describing: error), privacy: .public)")
            }
        }

        // Consumers re-read on the hook; firing without a rewrite would churn
        // them for nothing.
        if didRewriteFile {
            firePostMutateHook()
        }
    }

    private func logDiff(snapshot: TopologySnapshot, policies: LayoutPolicySet) {
        for d in snapshot.displays {
            TopologyLog.topology.debug("display id=\(d.id) builtIn=\(d.isBuiltIn) primary=\(d.isPrimaryMenuBarDisplay) frame=\(String(describing: d.framePoints), privacy: .public) density=\(d.densityClass.rawValue, privacy: .public)")
        }
        for p in policies.policies {
            TopologyLog.policy.debug("policy id=\(p.displayID) class=\(p.layoutClass.rawValue, privacy: .public) barH=\(p.barHeightPoints) maxSlots=\(p.maxVisibleSlots) aux=\(p.shouldUseAuxiliaryTopAreas)")
        }
    }

    private func firePostMutateHook() {
        let hook = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/workspace/hooks/post-mutate.sh")
        guard FileManager.default.isExecutableFile(atPath: hook.path) else { return }
        runIfAvailable(hook.path, ["topology"])
    }

    private func runIfAvailable(_ launchPath: String, _ args: [String]) {
        let proc = Process()
        proc.launchPath = launchPath
        proc.arguments = args
        do { try proc.run() } catch { /* daemon swallows; the next bump will retry */ }
    }
}
