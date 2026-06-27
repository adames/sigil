import AppKit
import SwiftUI

// MARK: - Shared overlay chrome
//
// One cross-overlay UI primitive: the reject "shake". The behind-window
// blur and the launch fade/scale used to live here too; both were removed
// for speed — overlays now paint a solid card in a small content-sized
// window and appear on the first runloop tick rather than fading in over a
// live-blurred desktop.

// MARK: - Shake (reject feedback)

/// A horizontal shake driven by an integer "nudge" counter: bump the
/// counter and the view jitters once. Used for rejected input (e.g. a
/// digit with no matching workspace) so a no-op is visible rather than
/// silent.
public struct Shake: GeometryEffect {
    public var animatableData: CGFloat
    private let amplitude: CGFloat
    private let shakes: CGFloat

    /// `animatableData` is the live (animating) value; pass an integer
    /// nudge counter cast to CGFloat. amplitude/shakes tune feel.
    public init(nudge: Int, amplitude: CGFloat = 7, shakes: CGFloat = 3) {
        self.animatableData = CGFloat(nudge)
        self.amplitude = amplitude
        self.shakes = shakes
    }

    public func effectValue(size: CGSize) -> ProjectionTransform {
        let dx = amplitude * sin(animatableData * .pi * shakes)
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}
