import Foundation
import Observation
import PeelCore

@Observable
final class HelperModel {
    private(set) var status = PrivilegedHelper.status
    private(set) var isChanging = false
    private(set) var isResponding: Bool?
    var failure: Failure?

    struct Failure {
        enum Action { case install, repair, uninstall }
        let action: Action
        let reason: String
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

    func refresh() {
        status = PrivilegedHelper.status
    }

    func checkConnection() async {
        status = await PrivilegedHelper.currentStatus()
        isResponding = status == .enabled ? await PrivilegedHelper.isResponding() : nil
        isRegisteredByAnotherCopy = status == .notRegistered ? await PrivilegedHelper.isRegisteredByAnyCopy() : false
    }

    /// Registers the helper, and opens Login Items settings when it needs the user's approval. Per
    /// `SMAppService.h`, registering a service that is already registered, or not approved by the user,
    /// throws an error. Neither is reported as a failure, since the status says what happened.
    func install() {
        do {
            try PrivilegedHelper.register()
        } catch {
            refresh()
            if status != .requiresApproval, status != .enabled {
                failure = Failure(action: .install, reason: error.localizedDescription)
            }
        }
        refresh()
        if status == .requiresApproval {
            PrivilegedHelper.openLoginItemsSettings()
        }
    }

    func repair() async {
        isChanging = true
        defer { isChanging = false }
        do {
            try await PrivilegedHelper.repair()
        } catch {
            failure = Failure(action: .repair, reason: error.localizedDescription)
        }
        refresh()
        if status == .requiresApproval {
            PrivilegedHelper.openLoginItemsSettings()
        }
        await checkConnection()
    }

    func uninstall() async {
        isChanging = true
        defer { isChanging = false }
        do {
            try await PrivilegedHelper.unregister()
        } catch {
            failure = Failure(action: .uninstall, reason: error.localizedDescription)
        }
        refresh()
    }
}
