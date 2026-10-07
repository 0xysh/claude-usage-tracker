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

    func testTwoProviderOverviewFitsWithoutScrollingPrimaryQuotas() throws {
        var claudeUsage = ClaudeUsage.empty
        claudeUsage.sessionPercentage = 23
        claudeUsage.weeklyPercentage = 78
        claudeUsage.fableUsageAvailable = true
        claudeUsage.fableWeeklyPercentage = 0
        claudeUsage.fableWeeklyResetTime = claudeUsage.weeklyResetTime
        let claude = Profile(name: "Claude Max · Personal account", claudeUsage: claudeUsage)
        var codexUsage = claudeUsage
        codexUsage.weeklyPercentage = 8
        codexUsage.fableUsageAvailable = false
        codexUsage.planType = "pro"
        codexUsage.creditsBalance = 62498.61
        codexUsage.lastUpdated = Date().addingTimeInterval(-1800)
        let codex = Profile(name: "Codex Pro · Personal account", provider: .codex, claudeUsage: codexUsage)

        for scheme in [ColorScheme.light, .dark] {
            let cards = VStack(spacing: 12) {
                ProfileUsageCard(profile: claude, error: nil, showRemaining: false,
                                 isRefreshing: false, onRefresh: {}, onPreferences: {})
                ProfileUsageCard(profile: codex, error: "Run Test Connection for this account.",
                                 showRemaining: false, isRefreshing: false,
                                 onRefresh: {}, onPreferences: {})
            }
            .padding(12)
            .frame(width: 360)
            .background(scheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color.white)
            .environment(\.colorScheme, scheme)
            let image = try XCTUnwrap(ImageRenderer(content: cards).nsImage)
            // The 680-point popup reserves 120 points for its header and mode picker.
            XCTAssertLessThanOrEqual(image.size.height + 120, 680,
                                     "Both providers' primary quotas must fit with account details collapsed.")
            try retain(image, name: "overview-\(scheme == .dark ? "dark" : "light")")
        }
    }

    func testUnifiedMenuBarRendersAllProvidersAndFableInOneLine() throws {
        var usage = ClaudeUsage.empty
        usage.weeklyPercentage = 78
        usage.fableUsageAvailable = true
        usage.fableWeeklyPercentage = 0
        var codexUsage = usage
        codexUsage.weeklyPercentage = 8
        codexUsage.fableUsageAvailable = false
        let selected = [Profile(name: "Codex Pro", provider: .codex, claudeUsage: codexUsage),
                        Profile(name: "Claude Max", claudeUsage: usage)]
        let renderer = MenuBarIconRenderer()
        for dark in [false, true] {
            for state in ["fresh", "saved", "missing"] {
                var profiles = selected
                if state == "saved" {
                    for index in profiles.indices { profiles[index].claudeUsage?.lastUpdated = .distantPast }
                } else if state == "missing" {
                    for index in profiles.indices { profiles[index].claudeUsage = nil }
                }
                let model = CombinedMenuBarPresentation(profiles: profiles, config: .default, errors: [:])
                let image = renderer.createCombinedProfileSummary(profiles: profiles, config: .default,
                                                                  errors: [:], isDarkMode: dark)
                XCTAssertEqual(image.size.width, model.reservedWidth)
                XCTAssertLessThanOrEqual(image.size.width, 480)
                XCTAssertEqual(image.size.height, 22)
                let canvas = NSImage(size: NSSize(width: image.size.width + 16, height: 38))
                canvas.lockFocus()
                (dark ? NSColor(white: 0.10, alpha: 1) : NSColor(white: 0.95, alpha: 1)).setFill()
                NSRect(origin: .zero, size: canvas.size).fill()
                image.draw(at: NSPoint(x: 8, y: 8), from: .zero, operation: .sourceOver, fraction: 1)
                canvas.unlockFocus()
                try retain(canvas, name: "unified-\(dark ? "dark" : "light")-\(state)")
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
