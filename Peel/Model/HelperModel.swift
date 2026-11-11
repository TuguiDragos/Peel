import Accessibility
import Foundation
import Observation
import PeelCore

@Observable
final class HelperModel {
    enum Action { case install, repair, uninstall }

    private(set) var status: PrivilegedHelper.Status
    private(set) var changing: Action?
    private(set) var isResponding: Bool?

    struct Failure {
        let action: Action
        let reason: String
    }

    var isChanging: Bool {
        changing != nil
    }

    /// Whether the helper can move items: it is registered and has not failed to answer, and for an account that isn't
    /// an administrator each action asks an administrator first. Otherwise the items that need it stay locked.
    var canAct: Bool {
        standing == .ready
    }

    var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    var standing: PrivilegedHelper.Standing {
        PrivilegedHelper.Standing(status: status, isAdministrator: isAdministrator, isResponding: isResponding)
    }

    private(set) var isAdministrator = PrivilegedHelper.isAdministrator

    /// True when a Peel helper is registered, but not by this copy of Peel. Registration belongs to a bundle,
    /// so a second copy (in a build folder, or a download beside the one in Applications) reads "not installed"
    /// while the first copy's helper is there. This lets it say why.
    private(set) var isRegisteredByAnotherCopy = false
    private(set) var hasChecked = false

    private var checks = OverlappingChecks()
    @ObservationIgnored private let performing: (Action) async throws -> Void
    @ObservationIgnored private let announcing: (AttributedString) -> Void
    @ObservationIgnored private let reading: () async -> Reading

    /// What a check of the helper reads: its status, whether this account is an administrator, whether the helper
    /// answers, and whether another copy of Peel registered it.
    struct Reading {
        var status: PrivilegedHelper.Status
        var isAdministrator: Bool
        var isResponding: Bool?
        var isRegisteredByAnotherCopy: Bool
    }

    init(
        performing: @escaping (Action) async throws -> Void = HelperModel.perform,
        announcing: @escaping (AttributedString) -> Void = { AccessibilityNotification.Announcement($0).post() },
        status: PrivilegedHelper.Status = PrivilegedHelper.status,
        reading: @escaping () async -> Reading = HelperModel.read
    ) {
        self.performing = performing
        self.announcing = announcing
        self.status = status
        self.reading = reading
    }

    /// Asks macOS and the helper, the helper only once it is registered.
    static func read() async -> Reading {
        let status = await PrivilegedHelper.currentStatus()
        let isAdministrator = await PrivilegedHelper.isAdministratorNow()
        let isResponding = status == .enabled ? await PrivilegedHelper.isResponding() : nil
        let isRegisteredByAnotherCopy = status == .notRegistered
            ? await PrivilegedHelper.isRegisteredByAnyCopy()
            : false
        return Reading(
            status: status, isAdministrator: isAdministrator, isResponding: isResponding,
            isRegisteredByAnotherCopy: isRegisteredByAnotherCopy
        )
    }

    /// What each change asks of macOS.
    static func perform(_ action: Action) async throws {
        switch action {
        case .install: try await PrivilegedHelper.register()
        case .repair: try await PrivilegedHelper.repair()
        case .uninstall: try await PrivilegedHelper.unregister()
        }
    }

    func checkConnection() async {
        let check = checks.start()
        let read = await reading()
        guard checks.mayShow(check) else { return }
        status = read.status
        isAdministrator = read.isAdministrator
        isResponding = read.isResponding
        isRegisteredByAnotherCopy = read.isRegisteredByAnotherCopy
        hasChecked = true
    }

    /// Registers the helper, and opens Login Items settings when it needs the user's approval. Per
    /// `SMAppService.h`, registering a service that is already registered, or not approved by the user,
    /// throws an error. Neither is reported as a failure, since the status says what happened.
    func install() async -> Failure? {
        guard !isChanging, !isRegisteredByAnotherCopy else { return nil }
        let (wasAllowed, error) = await change(.install)
        if wasAllowed, status == .requiresApproval {
            PrivilegedHelper.openLoginItemsSettings()
        }
        guard let error, status != .requiresApproval, status != .enabled else { return told(wasAllowed, nil) }
        return Failure(action: .install, reason: error.localizedDescription)
    }

    func repair() async -> Failure? {
        guard !isChanging else { return nil }
        let (wasAllowed, error) = await change(.repair)
        if wasAllowed, status == .requiresApproval {
            PrivilegedHelper.openLoginItemsSettings()
        }
        return told(wasAllowed, error.map { Failure(action: .repair, reason: $0.localizedDescription) })
    }

    func uninstall() async -> Failure? {
        guard !isChanging else { return nil }
        let (wasAllowed, error) = await change(.uninstall)
        return told(wasAllowed, error.map { Failure(action: .uninstall, reason: $0.localizedDescription) })
    }

    /// Runs a change of the helper's registration, for an administrator only, and answers whether it was allowed and
    /// its error. Nothing about the helper shows meanwhile; what it leaves shows through the check that follows.
    private func change(_ action: Action) async -> (wasAllowed: Bool, error: (any Error)?) {
        changing = action
        defer { changing = nil }
        checks.changeStarts()
        var wasAllowed = true
        var error: (any Error)?
        do {
            wasAllowed = try await PrivilegedHelper.changeAsAnAdministrator { try await performing(action) }
        } catch let thrown {
            error = thrown
        }
        checks.changeEnds()
        await checkConnection()
        return (wasAllowed, error)
    }

    /// Tells VoiceOver the helper's state in Settings' words once a change went through; a failure has an alert.
    private func told(_ wasAllowed: Bool, _ failure: Failure?) -> Failure? {
        if wasAllowed, failure == nil {
            announcing(AttributedString(localized: "\(String(localized: "Helper")): \(String(localized: stateWords))"))
        }
        return failure
    }
}
