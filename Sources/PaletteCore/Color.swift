import Foundation

// MARK: - sRGB color + OkLab math
//
// Pure, dependency-free color math shared by the palette resolver (which
// derives Sigil's gray ramp from a terminal's background→foreground) and
// the tests that pin the derived hexes. SwiftUI is deliberately absent —
// this builds into the `ws-topology` CLI, which must not pull in AppKit's
// color stack. The UI loader (WsUI) only reads hex strings out of the
// finished palette.json, so it doesn't need any of this.

/// An sRGB color with channels in [0, 1].
public struct RGB: Equatable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Parse `#RRGGBB` (a leading `#` is optional). Returns nil on any
    /// malformed input — same forgiving contract as the UI's Color(hex:).
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.r = Double((v >> 16) & 0xFF) / 255.0
        self.g = Double((v >> 8) & 0xFF) / 255.0
        self.b = Double(v & 0xFF) / 255.0
    }

    /// Render as lowercase `#rrggbb`. Channels are clamped to [0, 1] and
    /// rounded to the nearest 8-bit value.
    public var hex: String {
        func byte(_ c: Double) -> Int { Int((min(max(c, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(r), byte(g), byte(b))
    }
}

// MARK: - sRGB ↔ linear

private func srgbToLinear(_ c: Double) -> Double {
    c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
}

private func linearToSrgb(_ c: Double) -> Double {
    c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
}

// MARK: - OkLab

/// A color in the OkLab perceptual space (Björn Ottosson, 2020).
public struct OkLab: Equatable {
    public var L: Double
    public var a: Double
    public var b: Double

    public init(L: Double, a: Double, b: Double) {
        self.L = L
        self.a = a
        self.b = b
    }
}

public extension RGB {
    var oklab: OkLab {
        let lr = srgbToLinear(r)
        let lg = srgbToLinear(g)
        let lb = srgbToLinear(b)

        let l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
        let m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
        let s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb

        let l_ = cbrt(l)
        let m_ = cbrt(m)
        let s_ = cbrt(s)

        return OkLab(
            L: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        )
    }

    init(_ lab: OkLab) {
        let l_ = lab.L + 0.3963377774 * lab.a + 0.2158037573 * lab.b
        let m_ = lab.L - 0.1055613458 * lab.a - 0.0638541728 * lab.b
        let s_ = lab.L - 0.0894841775 * lab.a - 1.2914855480 * lab.b

        let l = l_ * l_ * l_
        let m = m_ * m_ * m_
        let s = s_ * s_ * s_

        self.r = linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)
        self.g = linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)
        self.b = linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }
}

// MARK: - Derivation helpers

public enum ColorMath {
    /// Linearly interpolate from `bg` to `fg` in OkLab at fraction `t`.
    /// `t` may sit outside [0, 1] to extrapolate "below background"
    /// (negative) — the resulting L is clamped to [0, 1] so a darken
    /// never folds past black. a/b are left unclamped (the extrapolated
    /// chroma stays in-line with the ramp's endpoints).
    public static func mix(_ bg: RGB, _ fg: RGB, _ t: Double) -> RGB {
        let a = bg.oklab
        let b = fg.oklab
        let lab = OkLab(
            L: min(max(a.L + (b.L - a.L) * t, 0), 1),
            a: a.a + (b.a - a.a) * t,
            b: a.b + (b.b - a.b) * t
        )
        return RGB(lab)
    }

    /// Nudge a color's OkLab lightness by `dL`, holding hue/chroma. Used
    /// to fabricate a bright accent sibling when a theme only defines the
    /// 8 normal ANSI colors (and vice-versa with a negative `dL`).
    public static func adjustLightness(_ c: RGB, by dL: Double) -> RGB {
        var lab = c.oklab
        lab.L = min(max(lab.L + dL, 0), 1)
        return RGB(lab)
    }

    /// WCAG contrast ratio between two colors (order-independent).
    public static func contrastRatio(_ x: RGB, _ y: RGB) -> Double {
        func relLum(_ c: RGB) -> Double {
            0.2126 * srgbToLinear(c.r) + 0.7152 * srgbToLinear(c.g) + 0.0722 * srgbToLinear(c.b)
        }
        let lx = relLum(x)
        let ly = relLum(y)
        let hi = max(lx, ly)
        let lo = min(lx, ly)
        return (hi + 0.05) / (lo + 0.05)
    }
}
