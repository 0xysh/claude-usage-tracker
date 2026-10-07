import XCTest
@testable import Claude_Usage

final class MenuBarUsagePresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testMissingReadingKeepsIdentityAndDoesNotInventPercentages() {
        let presentation = MenuBarUsagePresentation(usage: nil, refreshFailed: true, showRemaining: true, now: now)
        XCTAssertNil(presentation.sessionPercentage)
        XCTAssertNil(presentation.weeklyPercentage)
        let tooltip = presentation.tooltip(profileName: "Claude personal", showWeek: true, error: "Sign in again")
        XCTAssertTrue(tooltip.contains("Claude personal"))
        XCTAssertTrue(tooltip.contains("Unavailable"))
        XCTAssertTrue(tooltip.contains("Sign in again"))
        XCTAssertFalse(tooltip.contains("100%"))
    }

    func testUnavailableWindowIsNotZeroOrHundredPercent() {
        var usage = ClaudeUsage.empty
        usage.lastUpdated = now
        usage.sessionUsageAvailable = false
        usage.weeklyUsageAvailable = true
        usage.weeklyPercentage = 8
        for remaining in [false, true] {
            let presentation = MenuBarUsagePresentation(usage: usage, refreshFailed: false, showRemaining: remaining, now: now)
            XCTAssertNil(presentation.sessionPercentage)
            XCTAssertEqual(presentation.weeklyPercentage, remaining ? 92 : 8)
        }
    }

    func testExpiredCachedSessionPreservesLastMeasuredValue() {
        var usage = ClaudeUsage.empty
        usage.lastUpdated = now.addingTimeInterval(-600)
        usage.sessionResetTime = now.addingTimeInterval(-100)
        usage.sessionPercentage = 73
        let presentation = MenuBarUsagePresentation(usage: usage, refreshFailed: false, showRemaining: false, now: now)
        XCTAssertEqual(presentation.state, .lastKnown)
        XCTAssertEqual(presentation.sessionPercentage, 73)
    }

    func testInvalidCachedPercentagesRemainUnavailable() {
        for invalid in [Double.nan, Double.infinity, -1] {
            var usage = ClaudeUsage.empty
            usage.lastUpdated = now
            usage.sessionResetTime = now.addingTimeInterval(60)
            usage.sessionPercentage = invalid
            let presentation = MenuBarUsagePresentation(usage: usage, refreshFailed: false, showRemaining: false, now: now)
            XCTAssertNil(presentation.sessionPercentage)
            XCTAssertEqual(MenuBarUsagePresentation.percentageText(invalid), "—")
        }
    }

    func testTooltipExplainsBothWindowsAndPercentageMode() {
        var usage = ClaudeUsage.empty
        usage.lastUpdated = now
        usage.sessionResetTime = now.addingTimeInterval(60)
        usage.weeklyPercentage = 8
        let presentation = MenuBarUsagePresentation(usage: usage, refreshFailed: true, showRemaining: true, now: now)
        XCTAssertEqual(presentation.tooltip(profileName: "Codex", showWeek: true, error: nil),
                       "Codex\nLast known\nSession: 100% remaining\nWeekly: 92% remaining")
    }

    func testMenuBarWidthReservesThreeDigitsAndSavedBadge() {
        for width in [24.0, 41, 62, 78] {
            XCTAssertEqual(MenuBarUsagePresentation.itemLength(imageWidth: width, percentageStyle: true), 96)
        }
        XCTAssertEqual(MenuBarUsagePresentation.percentageText(125), "125%")
        XCTAssertEqual(MenuBarUsagePresentation.percentageText(Double.greatestFiniteMagnitude), "999%+")
    }
}
