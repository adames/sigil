import AppKit
import SwiftUI

// MARK: - Shared overlay chrome
//
// Cross-overlay UI primitives: the card shell + header (OverlayCard),
// the mode pill (ModeChip), and the reject "shake". ws-prompt and
// ws-picker used to each carry a byte-identical `card(width:)` and
// `header` — hoisted here once PR 5/6 made the two views' chrome
// genuinely identical apart from title, chip label, and accent color.
// The behind-window blur and the launch fade/scale used to live here
// too; both were removed for speed — overlays now paint a solid card in
// a small content-sized window and appear on the first runloop tick
// rather than fading in over a live-blurred desktop.

// MARK: - ModeChip

/// The small rounded pill in the header that names the overlay's mode
/// (e.g. "SEND", "FOCUS"). Fixed corner/height from `PromptStyle`, full-
/// color fill, dark Catppuccin text — only the label and accent color
/// vary per overlay.
public struct ModeChip: View {
    private let label: String
    private let accent: Color

    public init(_ label: String, accent: Color) {
        self.label = label
        self.accent = accent
    }

    public var body: some View {
        Text(label)
            .font(.system(size: PromptStyle.hintSize, weight: .medium))
            .foregroundColor(Palette.resolved.base)
            .padding(.horizontal, 10)
            .frame(height: PromptStyle.pillHeight)
            .background(
                RoundedRectangle(cornerRadius: PromptStyle.pillCorner)
                    .fill(accent)
            )
            .accessibilityLabel("\(label.lowercased()) mode")
    }
}

// MARK: - OverlayCard

/// The card shell + header shared by every prompt-style overlay
/// (ws-prompt, ws-picker): title on the left, `ModeChip` on the right,
/// then caller-supplied content, wrapped in the solid rounded card with
/// reject-flash border and shake. Card geometry, palette, and the
/// nudge/rejectFlash wiring are identical across overlays — only the
/// title, chip, and body content differ, so those are the parameters.
public struct OverlayCard<Content: View>: View {
    private let title: String
    private let width: CGFloat
    private let nudge: Int
    private let reduceMotion: Bool
    private let chip: ModeChip
    private let content: Content

    /// - Parameters:
    ///   - title: Header text (e.g. "send window", "find window").
    ///   - width: Card width, computed once from the host screen by the
    ///     owning App.
    ///   - nudge: The controller's reject-nudge counter; bump it to
    ///     shake the card once.
    ///   - reduceMotion: When true, the shake offset is skipped (the
    ///     card never moves) and the border pulse alone carries the
    ///     reject feedback.
    ///   - chip: The mode pill shown at the trailing edge of the header.
    ///   - content: Body rows between the header and the caller's own
    ///     footer/hint — the picker's query field is part of this.
    public init(
        title: String,
        width: CGFloat,
        nudge: Int,
        reduceMotion: Bool = false,
        chip: ModeChip,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.width = width
        self.nudge = nudge
        self.reduceMotion = reduceMotion
        self.chip = chip
        self.content = content()
    }

    /// True for a beat right after a reject, regardless of reduceMotion
    /// — a border-color pulse isn't motion, so it's the primary feedback
    /// when animation is off and a redundant cue otherwise.
    @State private var rejectFlash = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: width)
        .background(
            // Solid card — no behind-window blur. A flat mantle fill
            // paints instantly and stays crisp; the small window means
            // there's no full-screen surface to composite.
            RoundedRectangle(cornerRadius: PromptStyle.cardCorner)
                .fill(Palette.resolved.mantle)
                .overlay(
                    RoundedRectangle(cornerRadius: PromptStyle.cardCorner)
                        .strokeBorder(
                            rejectFlash ? Palette.resolved.red.opacity(0.85) : Palette.resolved.surface0.opacity(0.85),
                            lineWidth: rejectFlash ? 1.5 : 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
        .modifier(Shake(nudge: reduceMotion ? 0 : nudge))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: nudge)
        .onChange(of: nudge) { _, newValue in
            rejectFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                if nudge == newValue {
                    rejectFlash = false
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: PromptStyle.headerSize, weight: .medium))
                .foregroundColor(Palette.resolved.text)
            Spacer()
            chip
        }
    }
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
