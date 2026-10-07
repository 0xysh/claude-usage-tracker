import Foundation

/// One interpretation of availability and freshness for visual and accessible menu-bar content.
struct MenuBarUsagePresentation {
    let state: UsageDataState
    let sessionPercentage: Double?
    let weeklyPercentage: Double?
    let showRemaining: Bool

    init(usage: ClaudeUsage?, refreshFailed: Bool, showRemaining: Bool, now: Date = Date()) {
        self.showRemaining = showRemaining
        state = UsageDataState.resolve(lastUpdated: usage?.lastUpdated, refreshFailed: refreshFailed, now: now)
        guard let usage else {
            sessionPercentage = nil
            weeklyPercentage = nil
            return
        }
        // Cached readings stay as measured. A reset since that reading does not prove zero usage now.
        let session = state == .fresh && usage.sessionResetTime < now ? 0 : usage.sessionPercentage
        sessionPercentage = Self.display(session, available: usage.hasSessionUsage, showRemaining: showRemaining)
        weeklyPercentage = Self.display(usage.weeklyPercentage, available: usage.hasWeeklyUsage, showRemaining: showRemaining)
    }

    private static func display(_ used: Double, available: Bool, showRemaining: Bool) -> Double? {
        guard available, used.isFinite, used >= 0 else { return nil }
        return showRemaining ? max(0, 100 - used) : used
    }

    static func percentageText(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        if value > 999 { return "999%+" }
        // Avoid trapping on a corrupt but finite cached value outside Int's range.
        return String(format: "%.0f%%", value.rounded(.down))
    }

    static func itemLength(imageWidth: Double, percentageStyle: Bool) -> Double {
        // Reserve the cached-reading badge before it is needed. The normal
        // 0–999% range also reserves three digits so refreshes cannot resize it.
        max(percentageStyle ? 96 : 64, ceil((imageWidth + 11) / 32) * 32)
    }

    func tooltip(profileName: String, showWeek: Bool, error: String?) -> String {
        let mode = showRemaining ? "remaining" : "used"
        let freshness = state == .fresh ? "Fresh" : state == .lastKnown ? "Last known" : "Unavailable"
        var lines = [profileName, freshness, "Session: \(Self.percentageText(sessionPercentage)) \(mode)"]
        if showWeek { lines.append("Weekly: \(Self.percentageText(weeklyPercentage)) \(mode)") }
        if let error { lines.append(error) }
        if state == .unavailable { lines.append("Open to connect this account.") }
        return lines.joined(separator: "\n")
    }
}
