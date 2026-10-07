import XCTest
@testable import Claude_Usage

@MainActor
final class FableUsageTests: XCTestCase {
    private let service = ClaudeAPIService()

    func testLegacyReportedZeroIsAvailable() async throws {
        let usage = try decode(#"{"seven_day_fable":{"utilization":0,"resets_at":"2026-10-14T12:00:00.000Z"}}"#)
        XCTAssertTrue(usage.hasFableUsage)
        XCTAssertEqual(usage.fableWeeklyPercentage, 0)
        XCTAssertEqual(usage.fableWeeklyTokensUsed, 0)
        XCTAssertNotNil(usage.fableWeeklyResetTime)
    }

    func testScopedReportedZeroIsAvailableWithoutResetDate() async throws {
        let usage = try decode(#"{"seven_day_fable":null,"limits":[{"kind":"weekly_scoped","percent":0,"scope":{"model":{"id":null,"display_name":"Fable"}}}]}"#)
        XCTAssertTrue(usage.hasFableUsage)
        XCTAssertEqual(usage.fableWeeklyPercentage, 0)
        XCTAssertNil(usage.fableWeeklyResetTime)
    }

    func testScopedMythosIdentifierUsesReportedPercentage() async throws {
        let usage = try decode(#"{"limits":[{"kind":"weekly_scoped","percent":42.5,"resets_at":"2026-10-14T12:00:00Z","scope":{"model":{"id":"claude-mythos-1","display_name":"Renamed Model"}}}]}"#)
        XCTAssertTrue(usage.hasFableUsage)
        XCTAssertEqual(usage.fableWeeklyPercentage, 42.5)
        XCTAssertNotNil(usage.fableWeeklyResetTime)
    }

    func testMissingNullAndMalformedLegacyUsageAreUnavailable() async throws {
        for fixture in [#"{}"#, #"{"seven_day_fable":null}"#, #"{"seven_day_fable":{}}"#,
                        #"{"seven_day_fable":{"utilization":null}}"#,
                        #"{"seven_day_fable":{"utilization":"unknown","resets_at":"2026-10-14T12:00:00.000Z"}}"#] {
            let usage = try decode(fixture)
            XCTAssertFalse(usage.hasFableUsage, fixture)
            XCTAssertEqual(usage.fableWeeklyPercentage, 0)
            XCTAssertNil(usage.fableWeeklyResetTime)
        }
    }

    func testBooleansNegativeAndNonfiniteUsageAreUnavailable() async throws {
        for value in ["true", "false", "-1", #""NaN""#, #""Infinity""#] {
            let usage = try decode("{\"seven_day_fable\":{\"utilization\":\(value)}}")
            XCTAssertFalse(usage.hasFableUsage, value)
            XCTAssertEqual(usage.fableWeeklyPercentage, 0)
        }
    }

    func testScopedPercentageOverridesLegacyIncludingZero() async throws {
        let usage = try decode(#"{"seven_day_fable":{"utilization":73},"limits":[{"kind":"weekly_scoped","percent":0,"scope":{"model":{"id":"claude-fable","display_name":"Fable"}}}]}"#)
        XCTAssertTrue(usage.hasFableUsage)
        XCTAssertEqual(usage.fableWeeklyPercentage, 0)
    }

    func testInvalidOrMissingScopedPercentageCannotBecomeRealZeroOrReuseLegacy() async throws {
        for percent in ["", #", "percent":null"#, #", "percent":"unknown""#] {
            let usage = try decode("{\"seven_day_fable\":{\"utilization\":73},\"limits\":[{\"kind\":\"weekly_scoped\"\(percent),\"scope\":{\"model\":{\"display_name\":\"Fable\"}}}]}")
            XCTAssertFalse(usage.hasFableUsage, percent)
            XCTAssertEqual(usage.fableWeeklyPercentage, 0)
            XCTAssertNil(usage.fableWeeklyResetTime)
        }
    }

    func testUnrelatedAndNonweeklyScopedLimitsDoNotInventFable() async throws {
        let usage = try decode(#"{"limits":[{"kind":"weekly_scoped","percent":50,"scope":{"model":{"display_name":"Sonnet"}}},{"kind":"daily_scoped","percent":50,"scope":{"model":{"display_name":"Fable"}}}]}"#)
        XCTAssertFalse(usage.hasFableUsage)
    }

    func testNumericStringIsValidReportedUsage() async throws {
        let usage = try decode(#"{"seven_day_fable":{"utilization":" 0% "}}"#)
        XCTAssertTrue(usage.hasFableUsage)
        XCTAssertEqual(usage.fableWeeklyPercentage, 0)
    }

    func testOverLimitUsagePreservesReportedPercentage() async throws {
        let usage = try decode(#"{"seven_day_fable":{"utilization":125.5}}"#)
        XCTAssertTrue(usage.hasFableUsage)
        XCTAssertEqual(usage.fableWeeklyPercentage, 125.5)
    }

    func testEmbeddedOrRepeatedPercentSignsAreUnavailable() async throws {
        for value in ["0%%", "0%0", "%0", "0 % %"] {
            let usage = try decode("{\"seven_day_fable\":{\"utilization\":\"\(value)\"}}")
            XCTAssertFalse(usage.hasFableUsage, value)
        }
    }

    func testAvailabilitySurvivesPersistedRoundTripAtZero() async throws {
        let reported = try decode(#"{"seven_day_fable":{"utilization":0}}"#)
        let restored = try JSONDecoder().decode(ClaudeUsage.self, from: JSONEncoder().encode(reported))
        XCTAssertTrue(restored.hasFableUsage)
        XCTAssertEqual(restored.fableUsageAvailable, true)
    }

    func testExplicitUnavailableOverridesLegacyInferenceAfterRoundTrip() async throws {
        let fixture = #"{"fableWeeklyPercentage":73,"fableWeeklyTokensUsed":730000,"fableWeeklyResetTime":800000000,"fableUsageAvailable":false}"#
        let usage = try JSONDecoder().decode(ClaudeUsage.self, from: Data(fixture.utf8))
        XCTAssertFalse(usage.hasFableUsage)
        let restored = try JSONDecoder().decode(ClaudeUsage.self, from: JSONEncoder().encode(usage))
        XCTAssertFalse(restored.hasFableUsage)
    }

    func testLegacyPersistedAvailabilityInferencePreservesPositiveOrResetData() async throws {
        for fixture in [#"{"fableWeeklyPercentage":25}"#, #"{"fableWeeklyTokensUsed":10}"#,
                        #"{"fableWeeklyPercentage":0,"fableWeeklyResetTime":800000000}"#] {
            let usage = try JSONDecoder().decode(ClaudeUsage.self, from: Data(fixture.utf8))
            XCTAssertTrue(usage.hasFableUsage, fixture)
        }
        let unavailable = try JSONDecoder().decode(ClaudeUsage.self, from: Data(#"{"fableWeeklyPercentage":0}"#.utf8))
        XCTAssertFalse(unavailable.hasFableUsage)
        XCTAssertFalse(ClaudeUsage.empty.hasFableUsage)
    }

    private func decode(_ fixture: String) throws -> ClaudeUsage {
        try service.parseUsageResponse(Data(fixture.utf8))
    }
}
