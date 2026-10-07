import AppKit
import SwiftUI
import XCTest
@testable import Claude_Usage

@MainActor
final class CombinedUsageSizingTests: XCTestCase {
    func testShortDashboardFitsItsContentInsteadOfReservingTheScreenCap() async {
        let fixture = makeHost(profiles: [makeProfile()])
        defer { fixture.window.close() }
        let size = await settledSize(fixture.host)
        XCTAssertEqual(size.width, 360, accuracy: 1)
        XCTAssertGreaterThan(size.height, 150)
        XCTAssertLessThan(size.height, 450, "A weekly-only card must not reserve an empty tall viewport")
    }

    func testEmptyDashboardFitsItsMessage() async {
        let fixture = makeHost(profiles: [])
        defer { fixture.window.close() }
        let size = await settledSize(fixture.host)
        XCTAssertGreaterThan(size.height, 100)
        XCTAssertLessThan(size.height, 320)
    }

    func testDashboardGrowsToItsCapThenShrinksInTheSameHost() async {
        let short = [makeProfile()]
        let fixture = makeHost(profiles: short)
        defer { fixture.window.close() }
        let first = await settledSize(fixture.host)
        fixture.host.rootView = dashboard(profiles: (0..<6).map { _ in makeProfile() })
        let long = await settledSize(fixture.host)
        let cap = min(680, max(320, (NSScreen.main?.visibleFrame.height ?? 800) - 120))
        XCTAssertEqual(long.height, cap, accuracy: 1)
        XCTAssertGreaterThan(long.height, first.height + 100)
        fixture.host.rootView = dashboard(profiles: short)
        let last = await settledSize(fixture.host)
        XCTAssertEqual(last.height, first.height, accuracy: 1)
    }

    private func makeProfile() -> Profile {
        var usage = ClaudeUsage.empty
        usage.sessionUsageAvailable = false
        usage.weeklyUsageAvailable = true
        usage.weeklyPercentage = 15
        usage.planType = "pro"
        usage.creditsBalance = 10
        return Profile(name: "Synthetic Codex", provider: .codex, claudeUsage: usage)
    }

    private func dashboard(profiles: [Profile]) -> AnyView {
        AnyView(CombinedUsageView(profiles: profiles, errors: [:], isRefreshing: false,
                                  onRefresh: {}, onPreferences: {})
            .environment(\.usageMotionAllowed, false))
    }

    private func makeHost(profiles: [Profile]) -> (host: NSHostingController<AnyView>, window: NSWindow) {
        let host = NSHostingController(rootView: dashboard(profiles: profiles))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 680),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        return (host, window)
    }

    private func settledSize(_ host: NSHostingController<AnyView>) async -> CGSize {
        var previous = CGSize.zero
        var consecutive = 0
        for _ in 0..<60 {
            host.view.needsLayout = true
            host.view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(15))
            let size = host.sizeThatFits(in: CGSize(width: 360, height: 10_000))
            if size.height > 0, abs(size.height - previous.height) < 0.5 {
                consecutive += 1
                if consecutive >= 4 { return size }
            } else {
                consecutive = 0
            }
            previous = size
        }
        XCTFail("Dashboard intrinsic size did not settle within the bounded layout turns")
        return previous
    }
}
