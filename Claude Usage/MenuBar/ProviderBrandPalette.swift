import AppKit
import SwiftUI

/// Provider identity on labels, rails and controls. Quota health keeps its own semantic colors.
enum ProviderBrandPalette {
    static func accent(for provider: Provider, isDarkMode: Bool) -> NSColor {
        switch provider {
        case .anthropic:
            // Accessible UI adaptations of Claude's warm orange; original artwork is unchanged.
            return rgb(isDarkMode ? 0xF3AD8D : 0xA4492E)
        case .codex:
            // A UI identity accent, not a recoloring of the original monochrome OpenAI mark.
            return rgb(isDarkMode ? 0x91B8FF : 0x1F5BC8)
        }
    }

    static func color(for provider: Provider, scheme: ColorScheme) -> Color {
        Color(nsColor: accent(for: provider, isDarkMode: scheme == .dark))
    }

    /// WCAG relative-luminance contrast for opaque sRGB colors; alpha requires compositing first.
    static func contrastRatio(foreground: NSColor, background: NSColor) -> Double? {
        guard let foreground = luminance(foreground), let background = luminance(background) else { return nil }
        return (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static func luminance(_ color: NSColor) -> Double? {
        guard let color = color.usingColorSpace(.sRGB), color.alphaComponent == 1 else { return nil }
        let channels = [color.redComponent, color.greenComponent, color.blueComponent]
        guard channels.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        let linear = channels.map { channel -> Double in
            let value = Double(channel)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }
}
