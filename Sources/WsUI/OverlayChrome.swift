import AppKit
import SwiftUI

// MARK: - Shared overlay chrome
//
// Cross-overlay UI primitives that aren't palette tokens: the frosted
// background behind a card, the reveal transition every overlay plays on
// launch, and the reject "shake". Hoisted into WsUI so ws-prompt and
// ws-picker render identically — the two overlays are meant to feel like
// one tool.

/// `NSVisualEffectView` bridged into SwiftUI. Behind-window blending plus
/// the transparent borderless host window (see WsPromptApp/WsPickerApp)
/// frosts whatever desktop sits under the card, so the card's slight
/// translucency reads as glass instead of muddy color bleed.
public struct VisualEffectBlur: NSViewRepresentable {
    private let material: NSVisualEffectView.Material
    private let blending: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blending: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blending = blending
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

// MARK: - Reveal transition

/// The fade-and-scale every overlay plays when it appears. Borderless
/// modal panels otherwise pop in at full opacity over the live desktop,
/// which reads as a jarring flash; a short reveal softens the entrance
/// without slowing a power user down.
private struct OverlayReveal: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.97)
            .onAppear {
                withAnimation(.easeOut(duration: OverlayMotion.revealDuration)) {
                    shown = true
                }
            }
    }
}

public extension View {
    /// Play the standard overlay reveal (fade + slight scale-up) on appear.
    func overlayReveal() -> some View { modifier(OverlayReveal()) }
}

public enum OverlayMotion {
    /// Reveal/transition duration. Short enough not to gate input.
    public static let revealDuration: Double = 0.14
}

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
