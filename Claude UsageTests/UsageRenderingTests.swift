import XCTest
import AppKit
import SwiftUI
@testable import Claude_Usage

/// Offscreen renders use synthetic readings only; no launch, login or provider requests.
@MainActor
final class UsageRenderingTests: XCTestCase {
    private let output = URL(fileURLWithPath: "/private/tmp/claude-polish-audit/rendered", isDirectory: true)

    func testUsageCardsRenderInBothAppearancesAndConnectionStates() throws {
        var usage = ClaudeUsage.empty
        usage.sessionPercentage = 23
        usage.weeklyPercentage = 78
        usage.fableUsageAvailable = true
        usage.fableWeeklyPercentage = 0
        usage.fableWeeklyResetTime = usage.weeklyResetTime
        let fresh = Profile(name: "Claude Max · Personal account", claudeUsage: usage)
        var savedUsage = usage
        savedUsage.lastUpdated = Date().addingTimeInterval(-1800)
        savedUsage.sessionResetTime = Date().addingTimeInterval(-60)
        let saved = Profile(name: "Claude · Last received reading", claudeUsage: savedUsage)
        let disconnected = Profile(name: "Claude · A deliberately long account name that should wrap clearly", hasCliAccount: true)
        var codexUsage = usage
        codexUsage.sessionUsageAvailable = false
        codexUsage.weeklyPercentage = 8
        codexUsage.fableUsageAvailable = false
        let partial = Profile(name: "Codex Pro", provider: .codex, claudeUsage: codexUsage)

        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .dark ? "dark" : "light"
            for (name, profile, error) in [
                ("fresh-fable-zero", fresh, Optional<String>.none),
                ("saved", saved, nil),
                ("disconnected-long-name", disconnected, "Claude CLI credentials are missing a valid access token."),
                ("partial-codex", partial, nil)
            ] {
                let content = ProfileUsageCard(profile: profile, error: error, showRemaining: false,
                                              isRefreshing: false, onRefresh: {}, onPreferences: {})
                    .padding(12)
                    .frame(width: 360)
                    .background(scheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color.white)
                    .environment(\.colorScheme, scheme)
                let image = try XCTUnwrap(ImageRenderer(content: content).nsImage)
                XCTAssertEqual(image.size.width, 360, accuracy: 1)
                XCTAssertGreaterThan(image.size.height, 100)
                try retain(image, name: "\(appearance)-\(name)")
            }
        }
    }

    func testMenuBarFreshMissingAndSavedReadingsRender() throws {
        let renderer = MenuBarIconRenderer()
        for dark in [false, true] {
            for missing in [false, true] {
                let base = renderer.createMultiProfilePercentage(
                    sessionPercentage: missing ? nil : 0, weekPercentage: missing ? nil : 8,
                    sessionStatus: .safe, weekStatus: .safe, profileName: missing ? "Claude" : "Codex",
                    monochromeMode: missing, isDarkMode: dark, showWeek: true)
                try retain(base, name: "bar-\(dark ? "dark" : "light")-\(missing ? "missing" : "fresh")")
                if !missing {
                    try retain(renderer.createLastKnownIcon(from: base, isDarkMode: dark),
                               name: "bar-\(dark ? "dark" : "light")-saved")
                }
            }
        }
    }

    private func retain(_ image: NSImage, name: String) throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("\(name).png"))
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(image: image)
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }
}
