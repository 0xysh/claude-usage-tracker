import SwiftUI

/// The same provider data and usage rows as the individual popup, shown together.
struct CombinedUsageView: View {
    @StateObject private var profileManager = ProfileManager.shared
    let profiles: [Profile]
    let errors: [UUID: String]
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onPreferences: () -> Void

    private var availableHeight: CGFloat {
        min(680, max(320, (NSScreen.main?.visibleFrame.height ?? 800) - 120))
    }

    private var percentageDisplay: Binding<Bool> {
        Binding(
            get: { profileManager.multiProfileConfig.showRemainingPercentage },
            set: { showRemaining in
                var config = profileManager.multiProfileConfig
                config.showRemainingPercentage = showRemaining
                profileManager.updateMultiProfileConfig(config)
                // The existing update method publishes and saves on the next
                // main-loop turn. Notify icon observers after that same turn.
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .multiProfileConfigChanged, object: nil)
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your usage")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Claude & Codex")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HeaderIconButton(icon: "arrow.clockwise", isRefreshing: isRefreshing, action: onRefresh)
                    .disabled(isRefreshing)
                    .help("Refresh all accounts")
                HeaderIconButton(icon: "gearshape.fill", action: onPreferences)
                    .help("Settings")
            }
            .padding(16)

            Picker("Percentage display", selection: percentageDisplay) {
                Text("Used %").tag(false)
                Text("Remaining %").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    if profiles.isEmpty {
                        Text("Select accounts in Manage Profiles to see their usage together.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(20)
                    }
                    ForEach(profiles) { profile in
                        ProfileUsageCard(
                            profile: profile,
                            error: errors[profile.id],
                            showRemaining: profileManager.multiProfileConfig.showRemainingPercentage,
                            isRefreshing: isRefreshing,
                            onRefresh: onRefresh,
                            onPreferences: onPreferences
                        )
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 360, height: availableHeight)
    }
}

struct ProfileUsageCard: View {
    let profile: Profile
    let error: String?
    let showRemaining: Bool
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onPreferences: () -> Void

    private var accent: Color {
        profile.provider == .anthropic
            ? Color(red: 0.20, green: 0.77, blue: 0.57)
            : Color(red: 0.52, green: 0.51, blue: 0.96)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let state = UsageDataState.resolve(
                lastUpdated: profile.claudeUsage?.lastUpdated,
                refreshFailed: error != nil,
                now: timeline.date
            )
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            ProviderLogoView(provider: profile.provider, size: 15)
                            Text(profile.provider == .anthropic ? "Claude" : "Codex")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundStyle(accent)
                        Text(profile.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(state == .fresh ? "Fresh" : state == .lastKnown ? "Last known" : "Unavailable")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(state == .fresh ? accent : Color.orange)
                        if let updated = profile.claudeUsage?.lastUpdated {
                            Text(updated, style: .relative)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let usage = profile.claudeUsage {
                    Text(showRemaining ? "Remaining capacity" : "Used capacity")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    SmartUsageDashboard(usage: usage, apiUsage: profile.apiUsage, provider: profile.provider,
                                        showRemainingOverride: showRemaining)
                        .padding(.horizontal, -10)
                    if profile.provider == .anthropic, !usage.hasFableUsage {
                        Text("Fable · No quota reported")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("No usage data received", systemImage: "clock.badge.exclamationmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }

                if let error {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if state == .unavailable {
                    Text("Connect this account in Settings, then refresh.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(action: onRefresh) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                    Spacer()
                    if state != .fresh {
                        Button("Settings", action: onPreferences)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.borderless)
                .tint(accent)
            }
            .padding(14)
            .background(accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 3)
                    .padding(.vertical, 14)
            }
        }
    }
}
