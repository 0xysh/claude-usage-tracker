import XCTest
import AppKit
@testable import Claude_Usage

@MainActor
final class CombinedMenuBarPresentationTests: XCTestCase {
    private func profiles() -> [Profile] {
        var usage = ClaudeUsage.empty
        usage.sessionPercentage = 23
        usage.weeklyPercentage = 78
        usage.fableUsageAvailable = true
        usage.fableWeeklyPercentage = 0
        var codexUsage = usage
        codexUsage.weeklyPercentage = 8
        codexUsage.fableUsageAvailable = false
        return [Profile(name: "Codex Pro", provider: .codex, claudeUsage: codexUsage),
                Profile(name: "Claude Max", claudeUsage: usage)]
    }

    func testOrderedSelectedProvidersAndFableZero() {
        var selected = profiles()
        let hidden = Profile(name: "Hidden", provider: .codex, isSelectedForDisplay: false)
        selected.insert(hidden, at: 0)
        let model = CombinedMenuBarPresentation(profiles: selected, config: .default, errors: [:])
        XCTAssertEqual(model.segments.map(\.title), ["Codex", "Claude", "Fable"])
        XCTAssertEqual(model.segments.map(\.valueText), ["8%", "78%", "0%"])
        XCTAssertEqual(model.segments.map(\.period), ["7d", "7d", ""])
        XCTAssertTrue(model.tooltip.contains("Fable weekly: 0% used"))
    }

    func testRemainingModeUsesSameMetricsAndStableWidth() {
        var config = MultiProfileDisplayConfig.default
        let used = CombinedMenuBarPresentation(profiles: profiles(), config: config, errors: [:])
        config.showRemainingPercentage = true
        let remaining = CombinedMenuBarPresentation(profiles: profiles(), config: config, errors: [:])
        XCTAssertEqual(remaining.segments.map(\.valueText), ["92%", "22%", "100%"])
        XCTAssertEqual(used.reservedWidth, remaining.reservedWidth)
        XCTAssertTrue(remaining.tooltip.contains("Remaining quota"))
    }

    func testUnavailableMetricsKeepProviderAndFableLabels() {
        let selected = [Profile(name: "Codex", provider: .codex), Profile(name: "Claude")]
        let unavailable = CombinedMenuBarPresentation(profiles: selected, config: .default, errors: [:])
        XCTAssertEqual(unavailable.segments.map(\.valueText), ["—", "—", "—"])
        XCTAssertEqual(unavailable.reservedWidth,
                       CombinedMenuBarPresentation(profiles: profiles(), config: .default, errors: [:]).reservedWidth)
        XCTAssertTrue(unavailable.tooltip.contains("Fable weekly: No quota reported"))
        XCTAssertTrue(unavailable.segments.allSatisfy { $0.state == .unavailable })
    }

    func testMissingAndInvalidFableDoesNotInventZero() {
        for value in [Double.nan, -Double.infinity, -1] {
            var selected = profiles()
            selected[1].claudeUsage?.fableWeeklyPercentage = value
            let model = CombinedMenuBarPresentation(profiles: selected, config: .default, errors: [:])
            XCTAssertNil(model.segments.last?.percentage)
        }
        var selected = profiles()
        selected[0].claudeUsage?.weeklyUsageAvailable = false
        let model = CombinedMenuBarPresentation(profiles: selected, config: .default, errors: [:])
        XCTAssertNil(model.segments.first?.percentage)
        XCTAssertEqual(model.segments[1].percentage, 78)
    }

    func testSavedSessionRetainsMeasurementAndExplainsError() {
        var selected = profiles()
        selected[0].claudeUsage?.sessionPercentage = 72
        selected[0].claudeUsage?.sessionResetTime = Date().addingTimeInterval(-60)
        selected[0].claudeUsage?.lastUpdated = Date().addingTimeInterval(-1800)
        var config = MultiProfileDisplayConfig.default
        config.showWeek = false
        let model = CombinedMenuBarPresentation(profiles: selected, config: config,
                                               errors: [selected[0].id: "Reconnect this account."])
        XCTAssertEqual(model.segments[0].valueText, "72%")
        XCTAssertEqual(model.segments[0].period, "5h")
        XCTAssertEqual(model.segments[0].state, .lastKnown)
        XCTAssertEqual(model.segments.last?.period, "7d")
        XCTAssertTrue(model.tooltip.contains("Reconnect this account."))
    }

    func testMultipleAccountsHaveDistinctOrdinalLabelsAndFullTooltipNames() {
        let selected = [Profile(name: "Personal", provider: .codex), Profile(name: "Work", provider: .codex)]
        let model = CombinedMenuBarPresentation(profiles: selected, config: .default, errors: [:])
        XCTAssertEqual(model.segments.map(\.title), ["Codex 1", "Codex 2"])
        XCTAssertTrue(model.tooltip.contains("Personal"))
        XCTAssertTrue(model.tooltip.contains("Work"))
        XCTAssertEqual(CombinedMenuBarPresentation(profiles: [], config: .default, errors: [:]).reservedWidth, 64)
    }
}
