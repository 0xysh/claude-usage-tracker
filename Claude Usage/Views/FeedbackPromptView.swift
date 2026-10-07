//
//  FeedbackPromptView.swift
//  Claude Usage
//
//  Feedback collection popup — shown after 7 days of install.
//
//  Created by Claude Code on 2026-02-25.
//

import SwiftUI
import AppKit

// Feedback opens a browser draft in this fork. The user reviews and publishes it.

/// Role options for the feedback form
enum FeedbackRole: String, CaseIterable {
    case developer = "Developer"
    case designer = "Designer"
    case manager = "Manager"
    case student = "Student"
    case researcher = "Researcher"
    case other = "Other"

    var localized: String {
        switch self {
        case .developer: return "feedback.role_developer".localized
        case .designer: return "feedback.role_designer".localized
        case .manager: return "feedback.role_manager".localized
        case .student: return "feedback.role_student".localized
        case .researcher: return "feedback.role_researcher".localized
        case .other: return "feedback.role_other".localized
        }
    }
}

/// Feedback draft popup view — matches the GitHubStarPromptView style.
struct FeedbackPromptView: View {
    // Retained for existing callers. Opening a draft must not mark feedback submitted.
    let onSubmit: (_ name: String, _ role: String, _ contact: String, _ message: String) -> Void
    let onRemindLater: () -> Void
    let onDontAskAgain: () -> Void

    @State private var selectedRole: FeedbackRole = .developer
    @State private var message = ""
    @State private var showDraftOpened = false
    @State private var showOpenError = false
    @State private var openErrorMessageKey = "feedback.error_message"
    @State private var offersManualDraft = false

    @State private var isHoveringSubmit = false
    @State private var isHoveringRemind = false

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if showDraftOpened {
                draftOpenedContent
            } else {
                formContent
            }
        }
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 5)
        .alert("feedback.error_title".localized, isPresented: $showOpenError) {
            Button("common.ok".localized, role: .cancel) {}
        } message: {
            Text(openErrorMessageKey.localized)
        }
    }

    // MARK: - Form

    private var formContent: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("feedback.title".localized)
                        .font(.system(size: 13, weight: .semibold))
                    Text("feedback.subtitle".localized)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            // Fields
            VStack(spacing: 10) {
                // Role picker
                HStack {
                    Text("feedback.title_label".localized)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: $selectedRole) {
                        ForEach(FeedbackRole.allCases, id: \.self) { role in
                            Text(role.localized).tag(role)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )

                // Message
                TextEditor(text: $message)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
                    .overlay(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("feedback.message_placeholder".localized)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding(.horizontal, 20)

            Text("feedback.public_issue_notice".localized)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)

            if offersManualDraft {
                Button("feedback.open_empty_draft".localized, action: openEmptyDraft)
                    .font(.system(size: 11))
            }

            // Buttons
            HStack(spacing: 8) {
                Button(action: onRemindLater) {
                    Text("feedback.remind_later".localized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isHoveringRemind ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringRemind = $0 }

                Button(action: openDraft) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                        Text("feedback.submit".localized)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHoveringSubmit ? Color.accentColor.opacity(0.85) : Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1.0 : 0.5)
                .onHover { isHoveringSubmit = $0 }
            }
            .padding(.horizontal, 20)

            // Don't ask again
            Button(action: onDontAskAgain) {
                Text("feedback.never_show".localized)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
                    .underline()
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Browser Draft

    private var draftOpenedContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 24))
                .foregroundColor(.accentColor)

            Text("feedback.draft_opened".localized)
                .font(.system(size: 13, weight: .semibold))

            Text("feedback.draft_opened_desc".localized)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("feedback.edit_draft".localized) {
                showDraftOpened = false
            }
            .font(.system(size: 11))

            Button(action: onRemindLater) {
                Text("common.close".localized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    // MARK: - Open Draft

    private func openDraft() {
        guard canSubmit else { return }
        let result = FeedbackIssueURL.makeDraftURL(
            repositoryURL: Constants.GitHub.repoURL,
            role: selectedRole.rawValue,
            message: message
        )
        switch result {
        case .failure(.tooLong):
            openErrorMessageKey = "feedback.draft_too_long"
            offersManualDraft = true
            showOpenError = true
        case .failure:
            openErrorMessageKey = "feedback.error_message"
            showOpenError = true
        case .success(let url):
            guard NSWorkspace.shared.open(url) else {
                openErrorMessageKey = "feedback.error_message"
                showOpenError = true
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                showDraftOpened = true
            }
        }
    }

    private func openEmptyDraft() {
        guard let url = URL(string: Constants.GitHub.repoURL + "/issues/new"),
              NSWorkspace.shared.open(url) else {
            openErrorMessageKey = "feedback.error_message"
            showOpenError = true
            return
        }
        // Keep the form and its message available for the user's manual paste.
    }
}

// MARK: - Preview

#Preview {
    FeedbackPromptView(
        onSubmit: { _, _, _, _ in },
        onRemindLater: { print("Remind later") },
        onDontAskAgain: { print("Don't ask again") }
    )
    .padding(40)
}
