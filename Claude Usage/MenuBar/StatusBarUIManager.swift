//
//  StatusBarUIManager.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-27.
//

import Cocoa
import Combine

/// Owns the combined summary or the separate profile/metric menu bar items.
final class StatusBarUIManager {
    // Dictionary to hold multiple status items keyed by metric type (single profile mode)
    private var statusItems: [MenuBarMetricType: NSStatusItem] = [:]

    // Dictionary to hold status items keyed by profile ID (multi-profile mode)
    private var multiProfileStatusItems: [UUID: NSStatusItem] = [:]
    private var multiProfileOrder: [UUID] = []
    private var combinedStatusItem: NSStatusItem?

    // Current display mode
    private var isMultiProfileMode: Bool = false

    private var appearanceObservers: [NSKeyValueObservation] = []
    private var appearanceDebounceTimer: Timer?

    // Image cache to avoid redundant button.image assignments (which trigger KVO)
    private var lastImageData: [ObjectIdentifier: Data] = [:]

    // Icon renderer for creating menu bar images
    private let renderer = MenuBarIconRenderer()

    weak var delegate: StatusBarUIManagerDelegate?

    // MARK: - Stable autosaveName helpers

    /// Base prefix for all status item autosave names.
    /// Ice (icemenubar.app) and macOS use autosaveName to persist item positions.
    private static let autosavePrefix = "claudeUsageTracker"

    /// Returns a stable autosaveName for a single-profile metric item
    private static func autosaveName(for metricType: MenuBarMetricType) -> NSStatusItem.AutosaveName {
        return "\(autosavePrefix).metric.\(metricType.rawValue)"
    }

    /// Returns a stable autosaveName for a multi-profile item by profile ID
    private static func autosaveName(forProfileId id: UUID) -> NSStatusItem.AutosaveName {
        return "\(autosavePrefix).multiProfile.\(id.uuidString)"
    }
    /// Returns a stable autosaveName for the default logo (no credentials)
    private static let defaultLogoAutosaveName: NSStatusItem.AutosaveName = "\(autosavePrefix).defaultLogo"
    private static let combinedAutosaveName: NSStatusItem.AutosaveName = "\(autosavePrefix).combinedSummary"

    /// Fixed placeholder length for freshly-created multi-profile status items. Creating
    /// them at a concrete length (rather than .variableLength) avoids the macOS 26 (Tahoe)
    /// recursive variable-width NSISEngine solve during a multi-item rebuild (profile
    /// switch). updateMultiProfileButtons replaces it with the real coarse-rounded width.
    private static let multiProfilePlaceholderLength: CGFloat = 32

    // MARK: - Multi-profile identity helpers

    /// Well-known placeholder UUID used for the default logo in multi-profile mode
    private static let defaultLogoPlaceholderUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    // MARK: - Initialization

    init() {}

    // MARK: - Setup

    /// Sets up status bar items based on configuration
    func setup(target: AnyObject, action: Selector, config: MenuBarIconConfiguration) {
        // Remove all existing items first
        cleanup()

        // Check if there are any enabled metrics
        if config.enabledMetrics.isEmpty {
            // No credentials/metrics - show default app logo
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.autosaveName = Self.defaultLogoAutosaveName
            // Override any persisted false from a prior cmd-drag.
            statusItem.isVisible = true

            if let button = statusItem.button {
                button.action = action
                button.target = target
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                // Set a temporary placeholder - will be updated with actual logo
                button.title = ""
            } else {
                LoggingService.shared.logWarning("Status bar button is nil - screens: \(NSScreen.screens.count)")
            }

            // Use a special key to identify the default icon
            statusItems[.session] = statusItem  // Use session as placeholder key
            LoggingService.shared.logUIEvent("Status bar initialized with default app logo (no credentials)")
        } else {
            // Create status items for enabled metrics
            for metricConfig in config.enabledMetrics {
                let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                statusItem.autosaveName = Self.autosaveName(for: metricConfig.metricType)
                // Override any persisted false from a prior cmd-drag.
                statusItem.isVisible = true

                if let button = statusItem.button {
                    button.action = action
                    button.target = target
                    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                } else {
                    LoggingService.shared.logWarning("Status bar button is nil for \(metricConfig.metricType.displayName) - screens: \(NSScreen.screens.count)")
                }

                statusItems[metricConfig.metricType] = statusItem
            }

            LoggingService.shared.logUIEvent("Status bar initialized with \(config.enabledMetrics.count) metrics")
        }

        observeAppearanceChanges()
    }

    /// Updates status bar items based on new configuration (incremental approach)
    func updateConfiguration(target: AnyObject, action: Selector, config: MenuBarIconConfiguration) {
        guard !isMultiProfileMode, combinedStatusItem == nil else {
            setup(target: target, action: action, config: config)
            return
        }
        // Determine what the new set of items should be
        let newMetricTypes: Set<MenuBarMetricType>
        if config.enabledMetrics.isEmpty {
            // No credentials/metrics - show default app logo using .session as placeholder
            newMetricTypes = [.session]
        } else {
            newMetricTypes = Set(config.enabledMetrics.map { $0.metricType })
        }

        let currentMetricTypes = Set(statusItems.keys)

        // Step 1: Remove items that are no longer needed
        let itemsToRemove = currentMetricTypes.subtracting(newMetricTypes)
        for metricType in itemsToRemove {
            if let statusItem = statusItems[metricType] {
                if let button = statusItem.button {
                    lastImageData.removeValue(forKey: ObjectIdentifier(button))
                    button.image = nil
                    button.action = nil
                    button.target = nil
                }
                NSStatusBar.system.removeStatusItem(statusItem)
                LoggingService.shared.logUIEvent("Removed status item for \(metricType.displayName)")
            }
            statusItems.removeValue(forKey: metricType)
        }

        // Step 2: Add items that are new
        let itemsToAdd = newMetricTypes.subtracting(currentMetricTypes)
        for metricType in itemsToAdd {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            // When enabledMetrics is empty, only .session is in newMetricTypes, so this is safe
            statusItem.autosaveName = config.enabledMetrics.isEmpty
                ? Self.defaultLogoAutosaveName
                : Self.autosaveName(for: metricType)
            // Override any persisted false from a prior cmd-drag.
            statusItem.isVisible = true

            if let button = statusItem.button {
                button.action = action
                button.target = target
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                if metricType == .session {
                    // Default logo placeholder
                    button.title = ""
                }
            }

            statusItems[metricType] = statusItem
            LoggingService.shared.logUIEvent("Created status item for \(metricType.displayName)")
        }

        // Step 3: Items that already exist don't need recreation, just keep them
        // Their images will be updated by updateAllButtons() or updateButton()

        LoggingService.shared.logUIEvent("Status bar configuration updated: removed=\(itemsToRemove.count), added=\(itemsToAdd.count), kept=\(currentMetricTypes.intersection(newMetricTypes).count)")
    }

    func cleanup() {
        appearanceDebounceTimer?.invalidate()
        appearanceDebounceTimer = nil
        lastImageData.removeAll()
        appearanceObservers.forEach { $0.invalidate() }
        appearanceObservers.removeAll()

        // Clean up single profile status items
        for (_, statusItem) in statusItems {
            // Clear button references first
            if let button = statusItem.button {
                button.image = nil
                button.action = nil
                button.target = nil
            }
            // Then remove from status bar
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItems.removeAll()

        // Clean up multi-profile status items
        for (_, statusItem) in multiProfileStatusItems {
            if let button = statusItem.button {
                button.image = nil
                button.action = nil
                button.target = nil
            }
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        multiProfileStatusItems.removeAll()
        multiProfileOrder.removeAll()

        if let statusItem = combinedStatusItem {
            if let button = statusItem.button {
                button.image = nil
                button.action = nil
                button.target = nil
            }
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        combinedStatusItem = nil

        isMultiProfileMode = false

        LoggingService.shared.logUIEvent("Status bar cleaned up")
    }

    // MARK: - Multi-Profile Mode

    /// Creates one fixed-width summary item. Usage updates retain its identity.
    func setupCombinedProfileSummary(profiles: [Profile], config: MultiProfileDisplayConfig,
                                     errors: [UUID: String], target: AnyObject, action: Selector) {
        cleanup()
        let presentation = CombinedMenuBarPresentation(profiles: profiles, config: config, errors: errors)
        let item = NSStatusBar.system.statusItem(withLength: CGFloat(presentation.reservedWidth))
        item.autosaveName = Self.combinedAutosaveName
        item.isVisible = true
        if let button = item.button {
            button.title = ""
            button.action = action
            button.target = target
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = presentation.tooltip
            button.setAccessibilityLabel(presentation.tooltip)
        } else {
            LoggingService.shared.logWarning("Combined status bar button is nil - screens: \(NSScreen.screens.count)")
        }
        combinedStatusItem = item
        observeAppearanceChanges()
        LoggingService.shared.logUIEvent("Combined menu bar initialized with one status item")
    }

    /// Refreshes the existing item without a variable-width AppKit layout solve.
    func updateCombinedProfileSummary(profiles: [Profile], config: MultiProfileDisplayConfig,
                                      errors: [UUID: String]) {
        guard let item = combinedStatusItem, let button = item.button else { return }
        let presentation = CombinedMenuBarPresentation(profiles: profiles, config: config, errors: errors)
        let isDarkMode = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let image = renderer.createCombinedProfileSummary(profiles: profiles, config: config,
                                                         errors: errors, isDarkMode: isDarkMode)
        // The presentation reserves the same width for used/remaining, saved,
        // missing, and reported-zero values; only selection/layout changes resize.
        let width = CGFloat(presentation.reservedWidth)
        if abs(item.length - width) > 0.5 { item.length = width }
        button.title = ""
        button.toolTip = presentation.tooltip
        button.setAccessibilityLabel(presentation.tooltip)
        setButtonImage(button, image: image)
    }

    var isInCombinedProfileMode: Bool { combinedStatusItem != nil }

    /// The actual owned items, used to verify layout transitions and cleanup.
    var statusItemCount: Int {
        statusItems.count + multiProfileStatusItems.count + (combinedStatusItem == nil ? 0 : 1)
    }

    /// Sets up status bar for multi-profile display mode
    func setupMultiProfile(profiles: [Profile], target: AnyObject, action: Selector) {
        // Clean up existing items
        cleanup()

        isMultiProfileMode = true

        // Filter to only profiles selected for display
        let selectedProfiles = profiles.filter { $0.isSelectedForDisplay }
        multiProfileOrder = selectedProfiles.isEmpty
            ? [Self.defaultLogoPlaceholderUUID] : selectedProfiles.map(\.id)

        if selectedProfiles.isEmpty {
            // No profiles selected - show default logo
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.autosaveName = Self.defaultLogoAutosaveName
            // Override any persisted false from a prior cmd-drag.
            statusItem.isVisible = true
            if let button = statusItem.button {
                button.action = action
                button.target = target
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.title = ""
            } else {
                LoggingService.shared.logWarning("Multi-profile status bar button is nil - screens: \(NSScreen.screens.count)")
            }
            // Use a well-known placeholder UUID for default logo (stable across calls)
            multiProfileStatusItems[Self.defaultLogoPlaceholderUUID] = statusItem
            LoggingService.shared.logUIEvent("Multi-profile: No profiles selected, showing default logo")
        } else {
            // Create one status item per selected profile.
            // macOS 26 (Tahoe): creating these with .variableLength makes AppKit run a
            // recursive multi-item variable-width solve (NSISEngine) that overflows the
            // stack when a full setup rebuilds 2+ items — e.g. on profile switch. Start
            // them at a fixed placeholder length; updateMultiProfileButtons then pins the
            // real (coarse-rounded, stable) width. No variable-width solve, no recursion.
            for profile in selectedProfiles {
                let statusItem = NSStatusBar.system.statusItem(withLength: Self.multiProfilePlaceholderLength)
                statusItem.autosaveName = Self.autosaveName(forProfileId: profile.id)
                // Override any persisted false from a prior cmd-drag.
                statusItem.isVisible = true

                if let button = statusItem.button {
                    button.action = action
                    button.target = target
                    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                } else {
                    LoggingService.shared.logWarning("Multi-profile status bar button is nil for \(profile.name) - screens: \(NSScreen.screens.count)")
                }

                multiProfileStatusItems[profile.id] = statusItem
            }

            LoggingService.shared.logUIEvent("Multi-profile: Created \(selectedProfiles.count) status items")
        }

        observeAppearanceChanges()
    }

    /// Incrementally updates multi-profile status items without destroying existing ones.
    /// Only adds/removes items when the set of selected profiles changes.
    func updateMultiProfileConfiguration(profiles: [Profile], target: AnyObject, action: Selector) {
        guard isMultiProfileMode else {
            // Not in multi-profile mode yet - do a full setup
            setupMultiProfile(profiles: profiles, target: target, action: action)
            return
        }

        let selectedProfiles = profiles.filter { $0.isSelectedForDisplay }
        multiProfileOrder = selectedProfiles.isEmpty
            ? [Self.defaultLogoPlaceholderUUID] : selectedProfiles.map(\.id)
        let newProfileIds: Set<UUID> = selectedProfiles.isEmpty
            ? [Self.defaultLogoPlaceholderUUID]
            : Set(selectedProfiles.map { $0.id })
        let currentProfileIds = Set(multiProfileStatusItems.keys)

        // Step 1: Remove items that are no longer needed
        let idsToRemove = currentProfileIds.subtracting(newProfileIds)
        for profileId in idsToRemove {
            if let statusItem = multiProfileStatusItems[profileId] {
                if let button = statusItem.button {
                    lastImageData.removeValue(forKey: ObjectIdentifier(button))
                    button.image = nil
                    button.action = nil
                    button.target = nil
                }
                NSStatusBar.system.removeStatusItem(statusItem)
                LoggingService.shared.logUIEvent("Multi-profile: Removed status item for profile \(profileId)")
            }
            multiProfileStatusItems.removeValue(forKey: profileId)
        }

        // Step 2: Add items that are new
        let idsToAdd = newProfileIds.subtracting(currentProfileIds)

        if selectedProfiles.isEmpty && idsToAdd.contains(Self.defaultLogoPlaceholderUUID) {
            // Need to add default logo
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.autosaveName = Self.defaultLogoAutosaveName
            // Override any persisted false from a prior cmd-drag.
            statusItem.isVisible = true
            if let button = statusItem.button {
                button.action = action
                button.target = target
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.title = ""
            }
            multiProfileStatusItems[Self.defaultLogoPlaceholderUUID] = statusItem
            LoggingService.shared.logUIEvent("Multi-profile: Added default logo")
        } else {
            for profile in selectedProfiles where idsToAdd.contains(profile.id) {
                // Fixed placeholder length (see setupMultiProfile) — avoids the macOS 26
                // recursive variable-width solve; updateMultiProfileButtons pins the real width.
                let statusItem = NSStatusBar.system.statusItem(withLength: Self.multiProfilePlaceholderLength)
                statusItem.autosaveName = Self.autosaveName(forProfileId: profile.id)
                // Override any persisted false from a prior cmd-drag.
                statusItem.isVisible = true
                if let button = statusItem.button {
                    button.action = action
                    button.target = target
                    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                }
                multiProfileStatusItems[profile.id] = statusItem
                LoggingService.shared.logUIEvent("Multi-profile: Added status item for profile \(profile.name)")
            }
        }

        LoggingService.shared.logUIEvent("Multi-profile config updated: removed=\(idsToRemove.count), added=\(idsToAdd.count), kept=\(currentProfileIds.intersection(newProfileIds).count)")
    }

    /// Adds a thin green underline to an image to indicate the active profile
    private func addGreenUnderline(to image: NSImage) -> NSImage {
        let newImage = NSImage(size: image.size)
        newImage.lockFocus()
        defer { newImage.unlockFocus() }
        // Shift content up 2px to create a 1px gap above the underline
        image.draw(at: NSPoint(x: 0, y: 2), from: .zero, operation: .copy, fraction: 1.0)
        NSColor.systemGreen.setFill()
        NSBezierPath(rect: NSRect(x: 1, y: 0, width: image.size.width - 2, height: 1)).fill()
        return newImage
    }

    /// Updates all multi-profile status items
    func updateMultiProfileButtons(profiles: [Profile], config: MultiProfileDisplayConfig, activeProfileId: UUID? = nil, errors: [UUID: String] = [:]) {
        guard isMultiProfileMode else { return }

        for profile in profiles where profile.isSelectedForDisplay {
            guard let statusItem = multiProfileStatusItems[profile.id],
                  let button = statusItem.button else {
                continue
            }

            // Get actual menu bar appearance from the button (based on wallpaper, not system mode)
            let menuBarIsDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

            // Get usage data for this profile
            let presentation = MenuBarUsagePresentation(usage: profile.claudeUsage,
                                                       refreshFailed: errors[profile.id] != nil,
                                                       showRemaining: config.showRemainingPercentage)
            let description = presentation.tooltip(profileName: profile.name, showWeek: config.showWeek,
                                                   error: errors[profile.id])
            button.toolTip = description
            button.setAccessibilityLabel(description)
            guard let usage = profile.claudeUsage else {
                button.title = ""
                let image = renderer.createMultiProfilePercentage(
                    sessionPercentage: nil, weekPercentage: nil, sessionStatus: .safe, weekStatus: .safe,
                    profileName: config.showProfileLabel ? profile.name : nil,
                    monochromeMode: true, isDarkMode: menuBarIsDark, showWeek: config.showWeek)
                image.isTemplate = true
                let length = MenuBarUsagePresentation.itemLength(imageWidth: image.size.width,
                                                                 percentageStyle: config.iconStyle == .percentage)
                if abs(statusItem.length - length) > 0.5 { statusItem.length = length }
                setButtonImage(button, image: image)
                continue
            }
            button.title = ""
            let showRemaining = config.showRemainingPercentage

            // Calculate percentages
            let sessionUsed = presentation.state == .fresh ? usage.effectiveSessionPercentage : usage.sessionPercentage
            let weekUsed = usage.weeklyPercentage

            let sessionDisplay = UsageStatusCalculator.getDisplayPercentage(
                usedPercentage: sessionUsed,
                showRemaining: showRemaining
            )
            let weekDisplay = UsageStatusCalculator.getDisplayPercentage(
                usedPercentage: weekUsed,
                showRemaining: showRemaining
            )

            let sessionElapsed = UsageStatusCalculator.elapsedFraction(
                resetTime: usage.sessionResetTime,
                duration: Constants.sessionWindow,
                showRemaining: false
            )
            let weekElapsed = UsageStatusCalculator.elapsedFraction(
                resetTime: usage.weeklyResetTime,
                duration: Constants.weeklyWindow,
                showRemaining: false
            )
            let sessionStatus = UsageStatusCalculator.calculateStatus(
                usedPercentage: sessionUsed,
                showRemaining: showRemaining,
                elapsedFraction: config.usePaceColoring ? sessionElapsed : nil
            )
            let weekStatus = UsageStatusCalculator.calculateStatus(
                usedPercentage: weekUsed,
                showRemaining: showRemaining,
                elapsedFraction: config.usePaceColoring ? weekElapsed : nil
            )

            // Use multi-profile config's useSystemColor as monochrome mode
            // When useSystemColor is ON, icons will be white (like single-profile monochrome)
            let useMonochrome = config.useSystemColor

            // Calculate time marker fractions for multi-profile display
            let sessionMarker: CGFloat? = config.showTimeMarker
                ? sessionElapsed.map { CGFloat(showRemaining ? 1.0 - $0 : $0) }
                : nil
            let weekMarker: CGFloat? = config.showTimeMarker
                ? weekElapsed.map { CGFloat(showRemaining ? 1.0 - $0 : $0) }
                : nil

            // Compute pace status for multi-profile rendering
            let sessionPaceStatus: PaceStatus? = {
                guard config.showPaceMarker, let elapsed = sessionElapsed else { return nil }
                return PaceStatus.calculate(usedPercentage: sessionUsed, elapsedFraction: elapsed)
            }()
            let weekPaceStatus: PaceStatus? = {
                guard config.showPaceMarker, let elapsed = weekElapsed else { return nil }
                return PaceStatus.calculate(usedPercentage: weekUsed, elapsedFraction: elapsed)
            }()

            // Create icon based on selected style
            let image: NSImage
            let missingWindow = presentation.sessionPercentage == nil || (config.showWeek && presentation.weeklyPercentage == nil)
            switch missingWindow ? .percentage : config.iconStyle {
            case .concentric:
                if config.showProfileLabel {
                    image = renderer.createConcentricIconWithLabel(
                        sessionPercentage: sessionDisplay,
                        weekPercentage: config.showWeek ? weekDisplay : 0,
                        sessionStatus: sessionStatus,
                        weekStatus: weekStatus,
                        profileName: profile.name,
                        monochromeMode: useMonochrome,
                        isDarkMode: menuBarIsDark,
                        useSystemColor: false,
                        sessionTimeMarker: sessionMarker,
                        weekTimeMarker: config.showWeek ? weekMarker : nil,
                        sessionPaceStatus: sessionPaceStatus,
                        weekPaceStatus: config.showWeek ? weekPaceStatus : nil,
                        showPaceMarker: config.showPaceMarker
                    )
                } else {
                    image = renderer.createConcentricIcon(
                        sessionPercentage: sessionDisplay,
                        weekPercentage: config.showWeek ? weekDisplay : 0,
                        sessionStatus: sessionStatus,
                        weekStatus: weekStatus,
                        profileInitial: String(profile.name.prefix(1)),
                        monochromeMode: useMonochrome,
                        isDarkMode: menuBarIsDark,
                        useSystemColor: false,
                        sessionTimeMarker: sessionMarker,
                        weekTimeMarker: config.showWeek ? weekMarker : nil,
                        sessionPaceStatus: sessionPaceStatus,
                        weekPaceStatus: config.showWeek ? weekPaceStatus : nil,
                        showPaceMarker: config.showPaceMarker
                    )
                }
            case .progressBar:
                image = renderer.createMultiProfileProgressBar(
                    sessionPercentage: sessionDisplay,
                    weekPercentage: config.showWeek ? weekDisplay : nil,
                    sessionStatus: sessionStatus,
                    weekStatus: weekStatus,
                    profileName: config.showProfileLabel ? profile.name : nil,
                    monochromeMode: useMonochrome,
                    isDarkMode: menuBarIsDark,
                    useSystemColor: false,
                    sessionTimeMarker: sessionMarker,
                    weekTimeMarker: config.showWeek ? weekMarker : nil,
                    sessionPaceStatus: sessionPaceStatus,
                    weekPaceStatus: config.showWeek ? weekPaceStatus : nil,
                    showPaceMarker: config.showPaceMarker
                )
            case .compact:
                image = renderer.createCompactDot(
                    percentage: sessionDisplay,
                    status: sessionStatus,
                    profileInitial: config.showProfileLabel ? String(profile.name.prefix(1)) : nil,
                    monochromeMode: useMonochrome,
                    isDarkMode: menuBarIsDark,
                    useSystemColor: false,
                    paceStatus: sessionPaceStatus,
                    showPaceMarker: config.showPaceMarker
                )
            case .percentage:
                image = renderer.createMultiProfilePercentage(
                    sessionPercentage: presentation.sessionPercentage,
                    weekPercentage: config.showWeek ? presentation.weeklyPercentage : nil,
                    sessionStatus: sessionStatus,
                    weekStatus: weekStatus,
                    profileName: config.showProfileLabel ? profile.name : nil,
                    monochromeMode: useMonochrome,
                    isDarkMode: menuBarIsDark,
                    useSystemColor: false,
                    sessionPaceStatus: sessionPaceStatus,
                    weekPaceStatus: config.showWeek ? weekPaceStatus : nil,
                    showPaceMarker: config.showPaceMarker && presentation.state == .fresh && !missingWindow,
                    showWeek: config.showWeek
                )
            }

            let stateImage = presentation.state == .lastKnown
                ? renderer.createLastKnownIcon(from: image, isDarkMode: menuBarIsDark) : image
            let finalImage: NSImage
            if profile.id == activeProfileId && config.showActiveProfileIndicator {
                let underlinedImage = addGreenUnderline(to: stateImage)
                underlinedImage.isTemplate = false
                finalImage = underlinedImage
            } else {
                stateImage.isTemplate = useMonochrome && !config.showPaceMarker && presentation.state == .fresh
                finalImage = stateImage
            }

            // macOS 26 (Tahoe) crash fix: with NSStatusItem.variableLength, AppKit
            // recomputes each item's width from its image inside a shared status-bar
            // NSISEngine layout pass. With 2+ profile items this recurses without
            // termination — a stack overflow (___chkstk_darwin in NSISEngine
            // _coreReplaceMarker:withMarkerPlusDelta:). We pin an explicit length so
            // AppKit skips the recursive variable-width solve.
            //
            // Crucially the length must stay CONSTANT across refreshes: *changing* a
            // status item's length is itself the recursing op (the "PlusDelta"), so a
            // per-pixel width jitter between updates (e.g. "5%" vs "45%") would still
            // crash. Round the width up to a coarse grid so ordinary data changes never
            // move the length, and only assign when it genuinely changes.
            let stableLength = MenuBarUsagePresentation.itemLength(imageWidth: image.size.width,
                                                                  percentageStyle: config.iconStyle == .percentage || missingWindow)
            if abs(statusItem.length - stableLength) > 0.5 {
                statusItem.length = stableLength
            }
            setButtonImage(button, image: finalImage)
        }
    }

    /// Checks if currently in multi-profile mode
    var isInMultiProfileMode: Bool {
        return isMultiProfileMode
    }

    /// Checks if status bar has at least one valid button (for headless mode detection)
    var hasValidStatusBar: Bool {
        if combinedStatusItem?.button != nil { return true }
        // Check single-profile status items
        for (_, statusItem) in statusItems {
            if statusItem.button != nil {
                return true
            }
        }
        // Check multi-profile status items
        for (_, statusItem) in multiProfileStatusItems {
            if statusItem.button != nil {
                return true
            }
        }
        return false
    }

    /// Get button for a specific profile (multi-profile mode)
    func button(for profileId: UUID) -> NSStatusBarButton? {
        return multiProfileStatusItems[profileId]?.button
    }

    /// Find which profile ID owns the given button (multi-profile mode)
    func profileId(for sender: NSStatusBarButton?) -> UUID? {
        guard let sender = sender else { return nil }

        for (profileId, statusItem) in multiProfileStatusItems {
            if statusItem.button === sender {
                return profileId
            }
        }
        return nil
    }

    // MARK: - UI Updates

    /// Updates all status bar buttons based on current usage data
    func updateAllButtons(
        usage: ClaudeUsage,
        apiUsage: APIUsage?,
        usageAvailable: Bool = true,
        refreshFailed: Bool = false
    ) {
        // Get config from active profile
        let profile = ProfileManager.shared.activeProfile
        var config = profile?.iconConfig ?? .default
        if SharedDataStore.shared.loadPopoverShowAllProfiles() {
            config.showRemainingPercentage = ProfileManager.shared.multiProfileConfig.showRemainingPercentage
        }
        let presentation = MenuBarUsagePresentation(usage: usageAvailable ? usage : nil,
                                                   refreshFailed: refreshFailed,
                                                   showRemaining: config.showRemainingPercentage)
        let description = presentation.tooltip(profileName: profile?.name ?? "Usage", showWeek: true, error: nil)

        if !usageAvailable, !config.enabledMetrics.isEmpty {
            for (metric, item) in statusItems where metric != .api || apiUsage == nil {
                item.button?.title = ""
                item.button?.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "No usage data")
                item.button?.toolTip = description
                item.button?.setAccessibilityLabel(description)
                item.length = Self.multiProfilePlaceholderLength
            }
            if apiUsage != nil {
                updateButton(for: .api, usage: usage, apiUsage: apiUsage)
            }
            return
        }

        // Keep the render path aligned with ClaudeAPIService/MenuBarManager auth
        // fallback logic so users authenticated only via `claude login` don't
        // periodically repaint to the default logo after successful refreshes.
        let hasAnyCredentials = hasAnyAvailableCredentials(for: profile)
        if !hasAnyCredentials || config.enabledMetrics.isEmpty {
            // Show default app logo
            if let statusItem = statusItems[.session],  // We use .session as placeholder key
               let button = statusItem.button {
                // Get actual menu bar appearance from the button
                let menuBarIsDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let logoImage = renderer.createDefaultAppLogo(isDarkMode: menuBarIsDark)
                logoImage.isTemplate = true  // Let macOS handle the color
                setButtonImage(button, image: logoImage)
            }
            return
        }

        // Normal metric display
        for metricConfig in config.enabledMetrics {
            guard let statusItem = statusItems[metricConfig.metricType],
                  let button = statusItem.button else {
                continue
            }

            // Get actual menu bar appearance from the button
            let menuBarIsDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

            // Create image directly using our renderer
            let image = renderer.createImage(
                for: metricConfig.metricType,
                config: metricConfig,
                globalConfig: config,
                usage: usage,
                apiUsage: apiUsage,
                isDarkMode: menuBarIsDark,
                colorMode: config.colorMode,
                singleColorHex: config.singleColorHex,
                showIconName: config.showIconNames,
                showNextSessionTime: metricConfig.showNextSessionTime && presentation.state == .fresh,
                readingState: presentation.state
            )

            let unavailable = (metricConfig.metricType == .session && !usage.hasSessionUsage)
                || (metricConfig.metricType == .week && !usage.hasWeeklyUsage)
            let result: NSImage
            if unavailable {
                result = renderer.createMultiProfilePercentage(
                    sessionPercentage: nil, weekPercentage: nil, sessionStatus: .safe, weekStatus: .safe,
                    profileName: config.showIconNames ? metricConfig.metricType.displayName : nil,
                    monochromeMode: true, isDarkMode: menuBarIsDark, showWeek: false)
                result.isTemplate = true
            } else if presentation.state == .lastKnown && metricConfig.metricType != .api {
                result = renderer.createLastKnownIcon(from: image, isDarkMode: menuBarIsDark)
            } else {
                image.isTemplate = config.colorMode == .monochrome && !config.showPaceMarker
                result = image
            }
            button.toolTip = description
            button.setAccessibilityLabel(description)
            setButtonImage(button, image: result)
        }
    }

    /// Updates a specific metric's button
    func updateButton(
        for metricType: MenuBarMetricType,
        usage: ClaudeUsage,
        apiUsage: APIUsage?
    ) {
        guard let statusItem = statusItems[metricType],
              let button = statusItem.button else {
            return
        }

        // Get config from active profile
        var config = ProfileManager.shared.activeProfile?.iconConfig ?? .default
        if SharedDataStore.shared.loadPopoverShowAllProfiles() {
            config.showRemainingPercentage = ProfileManager.shared.multiProfileConfig.showRemainingPercentage
        }
        guard let metricConfig = config.config(for: metricType) else {
            return
        }

        // Get the actual menu bar appearance from the button's effective appearance
        let menuBarIsDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Create image directly using our renderer
        let image = renderer.createImage(
            for: metricType,
            config: metricConfig,
            globalConfig: config,
            usage: usage,
            apiUsage: apiUsage,
            isDarkMode: menuBarIsDark,
            colorMode: config.colorMode,
            singleColorHex: config.singleColorHex,
            showIconName: config.showIconNames,
            showNextSessionTime: metricConfig.showNextSessionTime
        )

        image.isTemplate = config.colorMode == .monochrome && !config.showPaceMarker
        button.image = image
    }

    /// Mirrors the auth fallback used for actual usage fetches so UI gating does
    /// not disagree with the network layer.
    private func hasAnyAvailableCredentials(for profile: Profile?) -> Bool {
        guard let profile else { return false }

        if profile.hasUsageCredentials { return true }

        do {
            if let systemCreds = try ClaudeCodeSyncService.shared.readSystemCredentials(),
               !ClaudeCodeSyncService.shared.isTokenExpired(systemCreds),
               ClaudeCodeSyncService.shared.extractAccessToken(from: systemCreds) != nil {
                return true
            }
        } catch {
            LoggingService.shared.log("StatusBarUIManager.hasAnyAvailableCredentials: system keychain check failed: \(error.localizedDescription)")
        }

        return false
    }

    /// Get button for a specific metric (used for popover positioning)
    func button(for metricType: MenuBarMetricType) -> NSStatusBarButton? {
        return statusItems[metricType]?.button
    }

    /// Finds an actual item, including combined/default and deselected-active cases.
    var primaryButton: NSStatusBarButton? {
        if let button = combinedStatusItem?.button { return button }
        let config = ProfileManager.shared.activeProfile?.iconConfig ?? .default
        for metric in config.enabledMetrics {
            if let button = statusItems[metric.metricType]?.button { return button }
        }
        if let button = statusItems[.session]?.button { return button }
        for id in multiProfileOrder {
            if let button = multiProfileStatusItems[id]?.button { return button }
        }
        return statusItems.values.compactMap(\.button).first
    }

    /// Find which metric type owns the given button (sender)
    func metricType(for sender: NSStatusBarButton?) -> MenuBarMetricType? {
        guard let sender = sender else { return nil }

        // Find which status item has this button
        for (metricType, statusItem) in statusItems {
            if statusItem.button === sender {
                return metricType
            }
        }
        return nil
    }

    // MARK: - Appearance Observation

    private var lastObservedAppearanceName: NSAppearance.Name?

    private func observeAppearanceChanges() {
        appearanceObservers.forEach { $0.invalidate() }
        appearanceObservers.removeAll()

        // IMPORTANT: Do NOT observe per-button effectiveAppearance.
        // Setting button.image triggers effectiveAppearance KVO on the button,
        // which causes an infinite redraw loop.
        let appObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, change in
            guard let self = self else { return }
            let newName = change.newValue?.name
            guard newName != self.lastObservedAppearanceName else { return }
            self.lastObservedAppearanceName = newName
            // Clear image cache so next update re-renders with new appearance
            self.lastImageData.removeAll()
            self.delegate?.statusBarAppearanceDidChange()
        }
        appearanceObservers.append(appObserver)
    }

    /// Only sets button.image if the image data actually changed.
    /// This prevents triggering effectiveAppearance KVO when the image is identical.
    private func setButtonImage(_ button: NSStatusBarButton, image: NSImage) {
        let buttonId = ObjectIdentifier(button)
        // Avoid NSImage.tiffRepresentation: macOS 26 SDK crashes in
        // SetupTIFFErrorHandler dispatch_once. Hash via CGImage bytes instead.
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let pixels = cg.dataProvider?.data as Data? else {
            button.image = image
            return
        }
        var newData = Data("\(cg.width):\(cg.height):\(image.isTemplate):".utf8)
        newData.append(pixels)
        if lastImageData[buttonId] == newData { return }
        lastImageData[buttonId] = newData
        button.image = image
    }

    /// Debounces appearance change notifications so multiple displays/buttons
    /// coalesce into a single delegate callback
    private func scheduleAppearanceUpdate() {
        appearanceDebounceTimer?.invalidate()
        appearanceDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.delegate?.statusBarAppearanceDidChange()
        }
    }
}

// MARK: - Delegate Protocol

protocol StatusBarUIManagerDelegate: AnyObject {
    func statusBarAppearanceDidChange()
}
