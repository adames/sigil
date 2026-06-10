import CoreGraphics
import Testing

@testable import DisplayTopology

/// Feeds the raw parameters of the display fixtures through the real
/// `DensityClass.classify` and checks they reproduce each fixture's
/// hand-labeled density class. Guards the pixel-width bucketing: a ppi-style
/// proxy that double-counts the backing scale would push every 2x external
/// into `.retinaLike` and leave `.midExternal` unreachable.
@Suite("Density classification")
struct DensityClassificationTests {

    @Test func fixtures_reclassify_to_their_hand_labeled_density() {
        let fixtures = [
            Fixtures.notchedM3Max(),
            Fixtures.compactM1(),
            Fixtures.external4K(),
            Fixtures.mirrorSecondary(masterID: 1),
        ]
        for display in fixtures {
            let classified = DensityClass.classify(
                backingScaleFactor: display.backingScaleFactor,
                pixelSize: display.pixelSize,
                isBuiltIn: display.isBuiltIn
            )
            #expect(classified == display.densityClass, "display \(display.id)")
        }
    }

    @Test func external_4k_at_2x_is_mid_external() {
        // 3840x2160 at 2x backing, 1920x1080 points — the external4K fixture.
        let classified = DensityClass.classify(
            backingScaleFactor: 2.0,
            pixelSize: CGSize(width: 3840, height: 2160),
            isBuiltIn: false
        )
        #expect(classified == .midExternal)
    }

    @Test func external_5k_at_2x_is_retina_like() {
        // 5K 27" (Studio Display class): 5120x2880 at 2x.
        let classified = DensityClass.classify(
            backingScaleFactor: 2.0,
            pixelSize: CGSize(width: 5120, height: 2880),
            isBuiltIn: false
        )
        #expect(classified == .retinaLike)
    }

    @Test func external_at_1x_is_coarse_regardless_of_pixel_width() {
        let classified = DensityClass.classify(
            backingScaleFactor: 1.0,
            pixelSize: CGSize(width: 3840, height: 2160),
            isBuiltIn: false
        )
        #expect(classified == .coarseExternal)
    }
}
