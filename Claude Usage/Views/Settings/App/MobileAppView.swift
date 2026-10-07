//
//  MobileAppView.swift
//  Claude Usage
//
//  Local interest preference for a potential mobile app.
//
//  Created by Claude Code on 2026-02-25.
//

import SwiftUI

/// Saves an interest preference on this Mac. No registration or notification service.
struct MobileAppView: View {
    // Preserve the existing key for users who already expressed interest.
    @AppStorage("mobileApp.notifyMe") private var isInterested = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "mobile.title".localized,
                    subtitle: "mobile.subtitle".localized
                )

                // Potential mobile app badge + icon
                HStack {
                    Spacer()
                    VStack(spacing: DesignTokens.Spacing.medium) {
                        Image(systemName: "iphone")
                            .font(.system(size: 28))
                            .foregroundColor(.accentColor)

                        Text("mobile.coming_soon_badge".localized)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1)
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.1))
                            )
                    }
                    Spacer()
                }

                Divider()

                // Interest is stored locally and can be withdrawn here.
                if isInterested {
                    HStack(spacing: DesignTokens.Spacing.medium) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: DesignTokens.Icons.standard))
                            .foregroundColor(SettingsColors.success)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("mobile.notified".localized)
                                .font(DesignTokens.Typography.bodyMedium)
                            Text("mobile.notified_desc".localized)
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(DesignTokens.Spacing.medium)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                            .fill(SettingsColors.lightOverlay(.green))
                    )

                    SettingsButton(
                        title: "mobile.clear_interest".localized,
                        icon: "xmark",
                        style: .secondary
                    ) {
                        isInterested = false
                    }
                } else {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                        Text("mobile.cta_message".localized)
                            .font(DesignTokens.Typography.body)
                            .foregroundColor(.secondary)

                        SettingsButton.primary(
                            title: "mobile.notify_me".localized,
                            icon: "bookmark",
                            action: { isInterested = true }
                        )
                    }
                }

                // Privacy note
                HStack(spacing: DesignTokens.Spacing.small) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: DesignTokens.Icons.tiny))
                        .foregroundColor(.secondary)
                    Text("mobile.privacy_note".localized)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(28)
        }
    }
}

#Preview {
    MobileAppView()
        .frame(width: 520, height: 600)
}
