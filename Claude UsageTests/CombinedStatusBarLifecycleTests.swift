import XCTest
import AppKit
@testable import Claude_Usage

private final class StatusBarTestTarget: NSObject {
    @objc func clicked(_ sender: Any?) {}
}

@MainActor
final class CombinedStatusBarLifecycleTests: XCTestCase {
    func testTwoAccountsUseOneItemAndRefreshRetainsItsIdentity() throws {
        let manager = StatusBarUIManager()
        defer { manager.cleanup() }
        let target = StatusBarTestTarget()
        let action = #selector(StatusBarTestTarget.clicked(_:))
        var selected = [Profile(name: "Codex", provider: .codex), Profile(name: "Claude")]
        manager.setupCombinedProfileSummary(profiles: selected, config: .default, errors: [:],
                                            target: target, action: action)
        manager.updateCombinedProfileSummary(profiles: selected, config: .default, errors: [:])
        XCTAssertEqual(manager.statusItemCount, 1)
        XCTAssertTrue(manager.isInCombinedProfileMode)
        let original = try XCTUnwrap(manager.primaryButton)
        let originalWidth = try XCTUnwrap(original.image).size.width
        selected[0].claudeUsage = .empty
        selected[0].claudeUsage?.weeklyPercentage = 8
        selected[1].claudeUsage = .empty
        selected[1].claudeUsage?.fableUsageAvailable = true
        var config = MultiProfileDisplayConfig.default
        config.showRemainingPercentage = true
        manager.updateCombinedProfileSummary(profiles: selected, config: config, errors: [:])
        XCTAssertEqual(manager.statusItemCount, 1)
        XCTAssertTrue(manager.primaryButton === original)
        XCTAssertEqual(original.image?.size.width, originalWidth)
        XCTAssertTrue(original.toolTip?.contains("Remaining quota") == true)

        manager.setupMultiProfile(profiles: selected, target: target, action: action)
        XCTAssertEqual(manager.statusItemCount, 2)
        XCTAssertFalse(manager.isInCombinedProfileMode)
        XCTAssertTrue(manager.isInMultiProfileMode)
        XCTAssertNotNil(manager.primaryButton)
        manager.cleanup()
        XCTAssertEqual(manager.statusItemCount, 0)
        XCTAssertNil(manager.primaryButton)
        XCTAssertFalse(manager.hasValidStatusBar)
    }

    func testFallbackButtonExistsWhenAnotherProfileIsDeselected() throws {
        let manager = StatusBarUIManager()
        defer { manager.cleanup() }
        let target = StatusBarTestTarget()
        let hidden = Profile(name: "Hidden", provider: .codex, isSelectedForDisplay: false)
        let shown = Profile(name: "Shown")
        manager.setupMultiProfile(profiles: [hidden, shown], target: target,
                                  action: #selector(StatusBarTestTarget.clicked(_:)))
        XCTAssertEqual(manager.statusItemCount, 1)
        XCTAssertNil(manager.button(for: hidden.id))
        XCTAssertTrue(manager.primaryButton === manager.button(for: shown.id))
        XCTAssertNotNil(manager.primaryButton)
    }
}
