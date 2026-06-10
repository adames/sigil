import AppKit
import CoreGraphics
import Foundation

/// Enumerates the live `NSScreen` set and combines it with Quartz Display Services
/// facts into a `TopologySnapshot`. The service does no caching; it is meant to be
/// called whenever a coalesced reconfiguration event fires.
///
/// All inputs are public AppKit/CoreGraphics surfaces: no private APIs.
public enum DisplayTopologyService {

    /// Capture the current topology snapshot. Must be called on the main thread —
    /// `NSScreen` access is documented as main-thread-only.
    @MainActor
    public static func snapshot() -> TopologySnapshot {
        let primaryID = CGMainDisplayID()
        let appMainID = NSScreen.main.flatMap(displayID(for:))

        let snapshots = NSScreen.screens.compactMap(displaySnapshot(from:))

        return TopologySnapshot(
            schemaVersion: 1,
            capturedAt: Date(),
            primaryDisplayID: primaryID,
            appMainDisplayID: appMainID,
            displays: snapshots
        )
    }

    @MainActor
    public static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let raw = screen.deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(raw.uint32Value)
    }

    @MainActor
    public static func displaySnapshot(from screen: NSScreen) -> DisplaySnapshot? {
        guard let id = displayID(for: screen) else { return nil }

        let mirrorMaster = CGDisplayMirrorsDisplay(id)
        let resolvedMirror: CGDirectDisplayID? =
            (mirrorMaster == kCGNullDirectDisplay) ? nil : mirrorMaster

        let pixelWidth  = CGDisplayPixelsWide(id)
        let pixelHeight = CGDisplayPixelsHigh(id)
        let pixelSize   = CGSize(width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))

        let backing = screen.backingScaleFactor

        let safeArea = EdgeInsetsCodable(
            top:    screen.safeAreaInsets.top,
            left:   screen.safeAreaInsets.left,
            bottom: screen.safeAreaInsets.bottom,
            right:  screen.safeAreaInsets.right
        )

        let auxLeft  = nonZeroRect(screen.auxiliaryTopLeftArea)
        let auxRight = nonZeroRect(screen.auxiliaryTopRightArea)

        let isBuiltIn  = CGDisplayIsBuiltin(id) != 0
        let isPrimary  = CGDisplayIsMain(id) != 0
        let isAppMain  = (NSScreen.main.flatMap(displayID(for:)) == id)

        let density = DensityClass.classify(
            backingScaleFactor: backing,
            pixelSize: pixelSize,
            isBuiltIn: isBuiltIn
        )

        return DisplaySnapshot(
            id: id,
            isBuiltIn: isBuiltIn,
            isPrimaryMenuBarDisplay: isPrimary,
            isAppMainDisplay: isAppMain,
            framePoints: screen.frame,
            visibleFramePoints: screen.visibleFrame,
            safeAreaInsets: safeArea,
            auxiliaryTopLeftArea: auxLeft,
            auxiliaryTopRightArea: auxRight,
            backingScaleFactor: backing,
            pixelSize: pixelSize,
            mirrorMasterID: resolvedMirror,
            densityClass: density,
            stableUUID: stableUUID(for: id)
        )
    }

    static func nonZeroRect(_ rect: CGRect?) -> CGRect? {
        guard let rect, rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    static func stableUUID(for id: CGDirectDisplayID) -> String? {
        guard let cf = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
        let uuid = cf.takeRetainedValue()
        let str  = CFUUIDCreateString(nil, uuid)
        return str as String?
    }
}

// MARK: - Density classification

extension DensityClass {
    /// Native pixel width at or above which an external display counts as
    /// retina-class (5K 27" panels are 5120x2880). 4K panels (3840 wide)
    /// deliberately fall below into `.midExternal`.
    static let retinaPixelWidthThreshold: CGFloat = 5120

    /// Buckets by native pixel width, not a physical-PPI proxy:
    /// `CGDisplayScreenSize` is documented as potentially estimated, so we
    /// never reason in inches. Sub-2x backing is `.coarseExternal`; built-in
    /// 2x panels are all retina-class; externals split at 5K.
    static func classify(
        backingScaleFactor: CGFloat,
        pixelSize: CGSize,
        isBuiltIn: Bool
    ) -> DensityClass {
        if backingScaleFactor < 2.0 {
            return .coarseExternal
        }
        if isBuiltIn {
            return .retinaLike
        }
        return pixelSize.width >= retinaPixelWidthThreshold ? .retinaLike : .midExternal
    }
}
