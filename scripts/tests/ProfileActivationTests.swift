import XCTest
@testable import Claude_Usage

@MainActor final class ProfileActivationTests: XCTestCase {
    override func setUp() async throws {
        let store = ProfileStore.shared
        store.stored = []
        store.activeID = nil
        store.saved = []
        store.lastPersistenceError = nil
        let sync = ClaudeCodeSyncService.shared
        sync.refresh = nil
        sync.refreshed = []
        sync.applied = []
        sync.resynced = []
        sync.resync = nil
        StatuslineService.shared.names = []
        let manager = ProfileManager.shared
        manager.profiles = []
        manager.activeProfile = nil
    }

    func testActivationRetainsRotatedCredentialsInMemoryAndDurableCommit() async throws {
        let previous = Profile(name: "Previous", provider: .codex)
        let target = Profile(name: "Target", cliCredentialsJSON: "synthetic-expired-snapshot")
        let store = ProfileStore.shared
        let manager = prepare(previous: previous, target: target)
        ClaudeCodeSyncService.shared.refresh = { id in
            let index = store.stored.firstIndex(where: { $0.id == id })!
            store.stored[index].cliCredentialsJSON = "synthetic-rotated-snapshot"
            store.stored[index].oauthAccountJSON = "synthetic-updated-account"
            return "synthetic-rotated-snapshot"
        }

        await manager.activateProfile(target.id)

        XCTAssertEqual(ClaudeCodeSyncService.shared.applied.first?.cliCredentialsJSON, "synthetic-rotated-snapshot")
        XCTAssertEqual(manager.activeProfile?.cliCredentialsJSON, "synthetic-rotated-snapshot")
        XCTAssertEqual(manager.activeProfile?.oauthAccountJSON, "synthetic-updated-account")
        XCTAssertEqual(manager.profiles.first(where: { $0.id == target.id })?.cliCredentialsJSON, "synthetic-rotated-snapshot")
        XCTAssertEqual(store.saved.last?.first(where: { $0.id == target.id })?.cliCredentialsJSON, "synthetic-rotated-snapshot")
        XCTAssertEqual(store.activeID, target.id)
        XCTAssertFalse(manager.isSwitchingProfile)
    }

    func testActivationPreservesOtherProfileEditsMadeDuringRefresh() async throws {
        let previous = Profile(name: "Previous", provider: .codex)
        let target = Profile(name: "Target", cliCredentialsJSON: "synthetic-old")
        let store = ProfileStore.shared
        let manager = prepare(previous: previous, target: target)
        ClaudeCodeSyncService.shared.refresh = { id in
            store.stored[0].name = "Previous edited during refresh"
            store.stored[1].cliCredentialsJSON = "synthetic-new"
            store.stored[1].name = "Target edited during refresh"
            store.stored[1].refreshInterval = 90
            return "synthetic-new"
        }

        await manager.activateProfile(target.id)

        XCTAssertEqual(manager.activeProfile?.name, "Target edited during refresh")
        XCTAssertEqual(manager.activeProfile?.refreshInterval, 90)
        XCTAssertEqual(store.stored[0].name, "Previous edited during refresh")
        XCTAssertEqual(StatuslineService.shared.names, ["Target edited during refresh"])
    }

    func testFailedRefreshPreservesExistingTargetSnapshot() async throws {
        let previous = Profile(name: "Previous", provider: .codex)
        let target = Profile(name: "Target", cliCredentialsJSON: "synthetic-existing")
        let manager = prepare(previous: previous, target: target)
        ClaudeCodeSyncService.shared.refresh = { _ in nil }

        await manager.activateProfile(target.id)

        XCTAssertEqual(manager.activeProfile?.cliCredentialsJSON, "synthetic-existing")
        XCTAssertEqual(ProfileStore.shared.stored[1].cliCredentialsJSON, "synthetic-existing")
        XCTAssertFalse(manager.isSwitchingProfile)
    }

    func testTargetRemovedDuringRefreshIsNotResurrectedAsActive() async throws {
        let previous = Profile(name: "Previous", provider: .codex)
        let target = Profile(name: "Target", cliCredentialsJSON: "synthetic-old")
        let store = ProfileStore.shared
        let manager = prepare(previous: previous, target: target)
        ClaudeCodeSyncService.shared.refresh = { id in
            store.stored.removeAll { $0.id == id }
            return "synthetic-new"
        }

        await manager.activateProfile(target.id)

        XCTAssertEqual(manager.activeProfile?.id, previous.id)
        XCTAssertEqual(store.activeID, previous.id)
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertFalse(manager.isSwitchingProfile)
        // An aborted switch must release the semaphore for a subsequent switch.
        let next = Profile(name: "Next", provider: .codex)
        store.stored.append(next)
        manager.profiles = store.stored
        await manager.activateProfile(next.id)
        XCTAssertEqual(manager.activeProfile?.id, next.id)
    }

    func testCodexActivationDoesNotApplyClaudeCredentials() async throws {
        let previous = Profile(name: "Previous", provider: .codex)
        let target = Profile(name: "Codex", provider: .codex, cliCredentialsJSON: "synthetic-legacy-field")
        let manager = prepare(previous: previous, target: target)

        await manager.activateProfile(target.id)

        XCTAssertTrue(ClaudeCodeSyncService.shared.refreshed.isEmpty)
        XCTAssertTrue(ClaudeCodeSyncService.shared.applied.isEmpty)
        XCTAssertEqual(manager.activeProfile?.id, target.id)
        XCTAssertGreaterThanOrEqual(manager.activeProfile!.lastUsedAt, target.lastUsedAt)
    }

    private func prepare(previous: Profile, target: Profile) -> ProfileManager {
        ProfileStore.shared.stored = [previous, target]
        ProfileStore.shared.activeID = previous.id
        let manager = ProfileManager.shared
        manager.profiles = [previous, target]
        manager.activeProfile = previous
        return manager
    }
}
