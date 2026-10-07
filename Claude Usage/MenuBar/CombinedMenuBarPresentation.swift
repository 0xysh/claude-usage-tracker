import AppKit

/// A single, stable-width summary of the selected accounts. Provider reads stay unchanged.
struct CombinedMenuBarPresentation {
    struct Segment {
        let profileID: UUID
        let provider: Provider
        let title: String
        let period: String
        let percentage: Double?
        let state: UsageDataState

        var valueText: String { MenuBarUsagePresentation.percentageText(percentage) }
    }

    let segments: [Segment]
    let tooltip: String

    init(profiles: [Profile], config: MultiProfileDisplayConfig, errors: [UUID: String], now: Date = Date()) {
        let selected = profiles.filter(\.isSelectedForDisplay)
        var result: [Segment] = []
        var fableSegments: [Segment] = []
        var descriptions = [config.showRemainingPercentage ? "Remaining quota" : "Used quota"]
        var ordinal: [Provider: Int] = [:]
        for profile in selected {
            let presentation = MenuBarUsagePresentation(usage: profile.claudeUsage,
                                                       refreshFailed: errors[profile.id] != nil,
                                                       showRemaining: config.showRemainingPercentage, now: now)
            ordinal[profile.provider, default: 0] += 1
            let multiple = selected.filter { $0.provider == profile.provider }.count > 1
            let suffix = multiple ? " \(ordinal[profile.provider, default: 1])" : ""
            let title = (profile.provider == .anthropic ? "Claude" : "Codex") + suffix
            result.append(Segment(profileID: profile.id, provider: profile.provider, title: title,
                                  period: config.showWeek ? "7d" : "5h",
                                  percentage: config.showWeek ? presentation.weeklyPercentage : presentation.sessionPercentage,
                                  state: presentation.state))
            var description = presentation.tooltip(profileName: profile.name, showWeek: true, error: errors[profile.id])
            if profile.provider == .anthropic {
                let usage = profile.claudeUsage
                let raw = usage?.fableWeeklyPercentage
                let valid = usage?.hasFableUsage == true && raw?.isFinite == true && (raw ?? -1) >= 0
                let value = valid ? raw.map { config.showRemainingPercentage ? max(0, 100 - $0) : $0 } : nil
                fableSegments.append(Segment(profileID: profile.id, provider: profile.provider, title: "Fable" + suffix,
                                             period: config.showWeek ? "" : "7d", percentage: value, state: presentation.state))
                description += valid ? "\nFable weekly: \(MenuBarUsagePresentation.percentageText(value)) \(config.showRemainingPercentage ? "remaining" : "used")"
                                     : "\nFable weekly: No quota reported"
            }
            descriptions.append(description)
        }
        segments = result + fableSegments
        tooltip = selected.isEmpty ? "Usage — select accounts in Manage Profiles." : descriptions.joined(separator: "\n\n")
    }

    var reservedWidth: Double {
        guard !segments.isEmpty else { return 64 }
        let content = segments.reduce(CGFloat.zero) { $0 + Self.width(for: $1) }
            + CGFloat(segments.count - 1) * Self.separatorWidth
        return Double(ceil(content + 4))
    }

    static let nameFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let periodFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    static let separatorFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let labelGap: CGFloat = 3
    static let separatorText = " | "
    static let savedIndicatorWidth: CGFloat = 12
    static var separatorWidth: CGFloat { textWidth(separatorText, font: separatorFont) }
    static var valueWidth: CGFloat { textWidth("999%+", font: valueFont) }

    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    static func width(for segment: Segment) -> CGFloat {
        textWidth(segment.title, font: nameFont) + labelGap
            + (segment.period.isEmpty ? 0 : textWidth(segment.period, font: periodFont) + labelGap)
            + valueWidth + savedIndicatorWidth // reserve the saved-reading clock without later resizing
    }
}

extension MenuBarIconRenderer {
    func createCombinedProfileSummary(profiles: [Profile], config: MultiProfileDisplayConfig,
                                      errors: [UUID: String], isDarkMode: Bool) -> NSImage {
        let presentation = CombinedMenuBarPresentation(profiles: profiles, config: config, errors: errors)
        let image = NSImage(size: NSSize(width: presentation.reservedWidth, height: 22))
        image.lockFocus()
        defer { image.unlockFocus() }
        let foreground = isDarkMode ? NSColor.white : NSColor.black
        let secondary = foreground.withAlphaComponent(isDarkMode ? 0.72 : 0.62)
        let warning = isDarkMode ? NSColor(red: 1, green: 0.73, blue: 0.29, alpha: 1)
                                : NSColor(red: 0.65, green: 0.36, blue: 0.04, alpha: 1)
        let critical = isDarkMode ? NSColor(red: 1, green: 0.40, blue: 0.37, alpha: 1)
                                 : NSColor(red: 0.74, green: 0.15, blue: 0.11, alpha: 1)
        func draw(_ text: String, x: CGFloat, font: NSFont, color: NSColor) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let height = (text as NSString).size(withAttributes: attributes).height
            (text as NSString).draw(at: NSPoint(x: x, y: (22 - height) / 2), withAttributes: attributes)
        }
        guard !presentation.segments.isEmpty else {
            draw("Usage", x: 5, font: CombinedMenuBarPresentation.nameFont, color: foreground)
            image.isTemplate = config.useSystemColor
            return image
        }
        var x: CGFloat = 2
        for (index, segment) in presentation.segments.enumerated() {
            if index > 0 {
                draw(CombinedMenuBarPresentation.separatorText, x: x,
                     font: CombinedMenuBarPresentation.separatorFont, color: secondary)
                x += CombinedMenuBarPresentation.separatorWidth
            }
            let width = CombinedMenuBarPresentation.width(for: segment)
            let accent = config.useSystemColor ? foreground
                : ProviderBrandPalette.accent(for: segment.provider, isDarkMode: isDarkMode)
            draw(segment.title, x: x, font: CombinedMenuBarPresentation.nameFont, color: accent)
            var next = x + CombinedMenuBarPresentation.textWidth(segment.title, font: CombinedMenuBarPresentation.nameFont)
                + CombinedMenuBarPresentation.labelGap
            if !segment.period.isEmpty {
                draw(segment.period, x: next, font: CombinedMenuBarPresentation.periodFont, color: secondary)
                next += CombinedMenuBarPresentation.textWidth(segment.period, font: CombinedMenuBarPresentation.periodFont)
                    + CombinedMenuBarPresentation.labelGap
            }
            let valueWidth = CombinedMenuBarPresentation.textWidth(segment.valueText, font: CombinedMenuBarPresentation.valueFont)
            let valueColor: NSColor
            if segment.state != .fresh || segment.percentage == nil {
                valueColor = secondary
            } else if config.useSystemColor {
                valueColor = foreground
            } else {
                let used = config.showRemainingPercentage ? 100 - (segment.percentage ?? 0) : (segment.percentage ?? 0)
                switch UsageStatusCalculator.calculateStatus(usedPercentage: used, showRemaining: config.showRemainingPercentage) {
                case .safe: valueColor = foreground
                case .moderate: valueColor = warning
                case .critical: valueColor = critical
                }
            }
            draw(segment.valueText, x: next + CombinedMenuBarPresentation.valueWidth - valueWidth,
                 font: CombinedMenuBarPresentation.valueFont, color: valueColor)
            if segment.state == .lastKnown && segment.percentage != nil,
               let clock = NSImage(systemSymbolName: "clock", accessibilityDescription: nil) {
                let symbol = clock.withSymbolConfiguration(.init(pointSize: 10, weight: .medium)) ?? clock
                // Template symbol tint works explicitly within the drawing context.
                let tinted = NSImage(size: symbol.size)
                tinted.lockFocus()
                symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
                (config.useSystemColor ? secondary : NSColor.systemOrange).setFill()
                NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
                tinted.unlockFocus()
                tinted.draw(in: NSRect(x: x + width - 11, y: 6, width: 10, height: 10))
            }
            x += width
        }
        image.isTemplate = config.useSystemColor
        return image
    }
}
