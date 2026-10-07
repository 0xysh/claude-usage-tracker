import AppKit
import XCTest
@testable import Claude_Usage

final class ProviderBrandPaletteTests: XCTestCase {
    func testProviderLabelsHaveAccessibleContrastOnTheirRepresentativeSurfaces() throws {
        let darkCard = NSColor(srgbRed: 29.0 / 255, green: 32.0 / 255, blue: 41.0 / 255, alpha: 1)
        for isDarkMode in [false, true] {
            for provider in Provider.allCases {
                let ratio = try XCTUnwrap(ProviderBrandPalette.contrastRatio(
                    foreground: ProviderBrandPalette.accent(for: provider, isDarkMode: isDarkMode),
                    background: isDarkMode ? darkCard : .white))
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "Small provider labels need readable contrast")
            }
        }
    }

    func testIdentityColorsRemainFiniteOpaqueAndDistinctInBothAppearances() throws {
        for isDarkMode in [false, true] {
            let claude = try XCTUnwrap(ProviderBrandPalette.accent(for: .anthropic, isDarkMode: isDarkMode)
                .usingColorSpace(.sRGB))
            let codex = try XCTUnwrap(ProviderBrandPalette.accent(for: .codex, isDarkMode: isDarkMode)
                .usingColorSpace(.sRGB))
            for color in [claude, codex] {
                for channel in [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent] {
                    XCTAssertTrue(channel.isFinite)
                    XCTAssertTrue((0...1).contains(channel))
                }
                XCTAssertEqual(color.alphaComponent, 1)
            }
            XCTAssertNotEqual(claude, codex)
            XCTAssertGreaterThan(claude.redComponent, claude.blueComponent, "Claude keeps its warm identity")
            XCTAssertGreaterThan(codex.blueComponent, codex.redComponent, "Codex keeps its blue UI identity")
        }
    }

    func testContrastCalculationUsesRelativeLuminanceAndIsSymmetric() throws {
        let blackOnWhite = try XCTUnwrap(ProviderBrandPalette.contrastRatio(foreground: .black, background: .white))
        XCTAssertEqual(blackOnWhite, 21, accuracy: 0.0001)
        XCTAssertEqual(ProviderBrandPalette.contrastRatio(foreground: .white, background: .black), blackOnWhite)
        XCTAssertEqual(ProviderBrandPalette.contrastRatio(foreground: .white, background: .white), 1)

        let gray = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        let ratio = try XCTUnwrap(ProviderBrandPalette.contrastRatio(foreground: gray, background: .white))
        XCTAssertEqual(ratio, 3.97665, accuracy: 0.0001)
    }

    func testTranslucentColorsRequireAResolvedBackgroundBeforeContrastIsClaimed() {
        XCTAssertNil(ProviderBrandPalette.contrastRatio(foreground: NSColor.black.withAlphaComponent(0.5),
                                                      background: .white))
        XCTAssertNil(ProviderBrandPalette.contrastRatio(foreground: .black,
                                                      background: NSColor.white.withAlphaComponent(0.5)))
    }
}
