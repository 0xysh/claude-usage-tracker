import SwiftUI

enum UsageMotionStyle {
    static let barHeight: CGFloat = 7
    static let entranceDuration = 0.6
    static let changeDuration = 0.28
}

/// Geometry is independent of animation and never trusts a cached percentage or marker.
enum UsageMotionGeometry {
    static func percentageFraction(_ percentage: Double) -> CGFloat {
        guard percentage.isFinite, percentage >= 0 else { return 0 }
        return CGFloat(min(percentage / 100, 1))
    }

    static func entranceProgress(_ progress: CGFloat, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 1 }
        guard progress.isFinite else { return 1 }
        return min(1, max(0, progress))
    }

    static func fillFraction(percentage: Double, progress: CGFloat, reduceMotion: Bool) -> CGFloat {
        percentageFraction(percentage) * entranceProgress(progress, reduceMotion: reduceMotion)
    }

    static func trackWidth(_ width: CGFloat) -> CGFloat {
        width.isFinite ? max(0, width) : 0
    }

    static func markerOrigin(fraction: CGFloat?, trackWidth: CGFloat, markerWidth: CGFloat = 2.5) -> CGFloat? {
        let width = self.trackWidth(trackWidth)
        guard let fraction, fraction.isFinite, width > 0,
              markerWidth.isFinite, markerWidth > 0 else { return nil }
        let visibleMarkerWidth = min(markerWidth, width)
        let center = min(1, max(0, fraction)) * width
        return min(width - visibleMarkerWidth, max(0, center - visibleMarkerWidth / 2))
    }

    /// Matches the visible formatter, so fractional changes and capped overflow do not roll.
    static func numericValue(_ percentage: Double?) -> Double? {
        guard let percentage, percentage.isFinite, percentage >= 0 else { return nil }
        return min(999, percentage.rounded(.down))
    }

    /// The entrance is visual only; accessibility and the underlying reading keep the target.
    static func presentedPercentage(_ percentage: Double?, progress: CGFloat, reduceMotion: Bool) -> Double? {
        guard let numeric = numericValue(percentage) else { return nil }
        let fraction = entranceProgress(progress, reduceMotion: reduceMotion)
        return fraction == 1 ? percentage : numeric * Double(fraction)
    }

    static func counterText(currentValue: Double, targetPercentage: Double?) -> String {
        guard let target = numericValue(targetPercentage) else { return MenuBarUsagePresentation.percentageText(nil) }
        guard currentValue.isFinite else { return MenuBarUsagePresentation.percentageText(targetPercentage) }
        let current = min(999, max(0, currentValue))
        if abs(current - target) < 0.001 {
            return MenuBarUsagePresentation.percentageText(targetPercentage)
        }
        return MenuBarUsagePresentation.percentageText(current)
    }

    static func counterBlur(currentValue: Double, targetValue: Double) -> CGFloat {
        guard currentValue.isFinite, targetValue.isFinite else { return 0 }
        return CGFloat(min(1.1, abs(currentValue - targetValue) * 0.12))
    }
}

private struct UsageEntranceProgressKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

private struct UsageMotionAllowedKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// A host can suppress motion for static previews; it cannot override system Reduce Motion.
    var usageMotionAllowed: Bool {
        get { self[UsageMotionAllowedKey.self] }
        set { self[UsageMotionAllowedKey.self] = newValue }
    }

    var usageEntranceProgress: CGFloat {
        get { self[UsageEntranceProgressKey.self] }
        set { self[UsageEntranceProgressKey.self] = newValue }
    }
}

/// One cancellable sweep for this presentation; quota refreshes do not replay it.
struct UsagePresentationMotion: ViewModifier {
    let presentationID: UUID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.usageMotionAllowed) private var motionAllowed
    @State private var progress: CGFloat = 0

    private var usesStaticPresentation: Bool { reduceMotion || !motionAllowed }

    private struct TaskIdentity: Equatable {
        let presentationID: UUID
        let reduceMotion: Bool
    }

    func body(content: Content) -> some View {
        content
            .environment(\.usageEntranceProgress,
                         UsageMotionGeometry.entranceProgress(progress, reduceMotion: usesStaticPresentation))
            .task(id: TaskIdentity(presentationID: presentationID, reduceMotion: usesStaticPresentation)) {
                guard !Task.isCancelled else { return }
                var reset = Transaction(animation: nil)
                reset.disablesAnimations = true
                withTransaction(reset) { progress = usesStaticPresentation ? 1 : 0 }
                guard !usesStaticPresentation else { return }

                // A separate main-queue transaction prevents SwiftUI coalescing reset and fill.
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.main.async { continuation.resume() }
                }
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: UsageMotionStyle.entranceDuration)) {
                    progress = 1
                }
            }
    }
}

struct UsageProgressBar: View {
    let percentage: Double
    let color: Color
    var markerFraction: CGFloat? = nil
    var markerColor: Color = .primary
    @Environment(\.usageEntranceProgress) private var entranceProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.usageMotionAllowed) private var motionAllowed
    @Environment(\.colorScheme) private var colorScheme

    private var usesStaticPresentation: Bool { reduceMotion || !motionAllowed }

    var body: some View {
        GeometryReader { proxy in
            let width = UsageMotionGeometry.trackWidth(proxy.size.width)
            let fraction = UsageMotionGeometry.fillFraction(
                percentage: percentage, progress: entranceProgress, reduceMotion: usesStaticPresentation)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.88), color],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: width * fraction)
            }
            .clipShape(Capsule())
            .animation(usesStaticPresentation ? nil : .easeOut(duration: UsageMotionStyle.changeDuration),
                       value: UsageMotionGeometry.percentageFraction(percentage))
            .overlay(alignment: .leading) {
                if let origin = UsageMotionGeometry.markerOrigin(fraction: markerFraction, trackWidth: width) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(markerColor)
                        .frame(width: min(2.5, width), height: 11)
                        .offset(x: origin)
                }
            }
        }
        .frame(height: UsageMotionStyle.barHeight)
        .accessibilityHidden(true)
        .transaction {
            if usesStaticPresentation {
                $0.animation = nil
                $0.disablesAnimations = true
            }
        }
    }
}

/// Real per-frame interpolation, rather than a glyph transition between two endpoint strings.
private struct CountingPercentageText: View, Animatable {
    var value: Double
    let targetPercentage: Double?

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        let targetText = MenuBarUsagePresentation.percentageText(targetPercentage)
        // Reserve the target's width so digit-count changes cannot move neighboring content.
        Text(targetText)
            .hidden()
            .overlay(alignment: .trailing) {
                Text(UsageMotionGeometry.counterText(currentValue: value, targetPercentage: targetPercentage))
                    .blur(radius: UsageMotionGeometry.counterBlur(
                        currentValue: value, targetValue: UsageMotionGeometry.numericValue(targetPercentage) ?? 0))
            }
    }
}

/// The visible counter shares the bar's entrance transaction; accessibility keeps the target.
struct UsagePercentageText: View {
    let percentage: Double?
    @Environment(\.usageEntranceProgress) private var entranceProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.usageMotionAllowed) private var motionAllowed

    private var usesStaticPresentation: Bool { reduceMotion || !motionAllowed }

    private var targetText: String { MenuBarUsagePresentation.percentageText(percentage) }

    private var presentedPercentage: Double? {
        UsageMotionGeometry.presentedPercentage(percentage, progress: entranceProgress, reduceMotion: usesStaticPresentation)
    }

    var body: some View {
        Group {
            if usesStaticPresentation || UsageMotionGeometry.numericValue(percentage) == nil {
                Text(targetText)
            } else {
                CountingPercentageText(value: UsageMotionGeometry.numericValue(presentedPercentage) ?? 0,
                                       targetPercentage: percentage)
                    // Entrance changes inherit their shared 600ms transaction. Only an actual
                    // formatted reading change gets the shorter data-update transaction.
                    .animation(.easeOut(duration: UsageMotionStyle.changeDuration), value: targetText)
            }
        }
        .monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(targetText)
        .transaction {
            if usesStaticPresentation {
                $0.animation = nil
                $0.disablesAnimations = true
            }
        }
    }
}
