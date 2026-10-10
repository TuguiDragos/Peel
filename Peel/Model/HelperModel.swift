import Foundation
import Observation
import PeelCore

@Observable
final class HelperModel {
    enum Action { case install, repair, uninstall }

    private(set) var status = PrivilegedHelper.status
    private(set) var changing: Action?
    private(set) var isResponding: Bool?

    struct Failure {
        let action: Action
        let reason: String
    }

    var isChanging: Bool {
        changing != nil
    }

    /// Whether the helper can move items: it is registered, this account may use it, and it has not failed to
    /// answer. Otherwise the items that need it stay locked.
    var canAct: Bool {
        standing == .ready
    }

    var isEnabled: Bool {
        status == .enabled
    }

    var standing: PrivilegedHelper.Standing {
        PrivilegedHelper.Standing(
            status: status, isAvailableToThisAccount: isAvailableToThisAccount, isResponding: isResponding
        )
    }

    let isAvailableToThisAccount = PrivilegedHelper.isAvailableToThisAccount

    /// True when a Peel helper is registered, but not by this copy of Peel. Registration belongs to a bundle,
    /// so a second copy (in a build folder, or a download beside the one in Applications) reads "not installed"
    /// while the first copy's helper is there. This lets it say why.
    private(set) var isRegisteredByAnotherCopy = false
    private(set) var hasChecked = false

    private var checks = OverlappingChecks()

    func checkConnection() async {
        let check = checks.start()
        let status = await PrivilegedHelper.currentStatus()
        let isResponding = status == .enabled ? await PrivilegedHelper.isResponding() : nil
        let isRegisteredByAnotherCopy = status == .notRegistered
            ? await PrivilegedHelper.isRegisteredByAnyCopy()
            : false
        guard checks.mayShow(check) else { return }
        self.status = status
        self.isResponding = isResponding
        self.isRegisteredByAnotherCopy = isRegisteredByAnotherCopy
        hasChecked = true
    }

    /// Registers the helper, and opens Login Items settings when it needs the user's approval. Per
    /// `SMAppService.h`, registering a service that is already registered, or not approved by the user,
    /// throws an error. Neither is reported as a failure, since the status says what happened.
    func install() async -> Failure? {
        guard !isChanging else { return nil }
        let error = await change(.install) { try await PrivilegedHelper.register() }
        if status == .requiresApproval {
            PrivilegedHelper.openLoginItemsSettings()
        }
        guard let error, status != .requiresApproval, status != .enabled else { return nil }
        return Failure(action: .install, reason: error.localizedDescription)
    }

    func repair() async -> Failure? {
        guard !isChanging else { return nil }
        let error = await change(.repair) { try await PrivilegedHelper.repair() }
        if status == .requiresApproval {
            PrivilegedHelper.openLoginItemsSettings()
        }
        return error.map { Failure(action: .repair, reason: $0.localizedDescription) }
    }

    func uninstall() async -> Failure? {
        guard !isChanging else { return nil }
        let error = await change(.uninstall) { try await PrivilegedHelper.unregister() }
        return error.map { Failure(action: .uninstall, reason: $0.localizedDescription) }
    }

    /// Runs a change of the helper's registration and answers the error it threw, if any. Nothing about the helper
    /// shows while it runs, and what it leaves shows only through the check that follows it.
    private func change(_ action: Action, _ body: () async throws -> Void) async -> (any Error)? {
        changing = action
        defer { changing = nil }
        checks.changeStarts()
        var error: (any Error)?
        do {
            try await body()
        } catch let thrown {
            error = thrown
        }
        checks.changeEnds()
        await checkConnection()
        return error
    }
}
