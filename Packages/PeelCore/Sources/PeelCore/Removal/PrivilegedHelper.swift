public import Foundation
import PeelPrivileged
import ServiceManagement
import Synchronization

public enum PrivilegedHelper {
    static let unavailable = "Peel’s helper isn’t available."

    public enum Status: Sendable, Equatable {
        case notRegistered
        case requiresApproval
        case enabled
        case unavailable
    }

    /// Whether the helper can act for this account, and if not, why.
    public enum Standing: Sendable, Equatable {
        case ready
        case notInstalled
        case waitingForApproval
        case notThisAccount
        case notAnswering

        /// A standard account comes first: the helper serves administrators only, so its registration says nothing
        /// that account could act on.
        public init(status: Status, isAvailableToThisAccount: Bool, isResponding: Bool?) {
            guard isAvailableToThisAccount else {
                self = .notThisAccount
                return
            }
            self = switch status {
            case .enabled: isResponding == false ? .notAnswering : .ready
            case .requiresApproval: .waitingForApproval
            case .notRegistered, .unavailable: .notInstalled
            }
        }
    }

    private static var service: SMAppService {
        .daemon(plistName: HelperIdentity.launchdPlistName)
    }

    public static var status: Status {
        switch service.status {
        case .notRegistered: .notRegistered
        case .requiresApproval: .requiresApproval
        case .enabled: .enabled
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    public static func register() throws {
        try service.register()
    }

    public static func unregister() async throws {
        try await service.unregister()
    }

    /// Unregisters the helper and registers it again. `SMAppService` refuses to register a service that is
    /// already registered, so a helper left by an older version of Peel can only be replaced this way.
    public static func repair() async throws {
        var unregistering: (any Error)?
        do {
            try await service.unregister()
        } catch {
            unregistering = error
        }
        do {
            try service.register()
        } catch {
            throw repairFailure(registering: error, afterUnregistering: unregistering)
        }
    }

    /// Why a repair failed. A helper that could not be unregistered is still registered, and registering it again
    /// only answers `kSMErrorAlreadyRegistered`, so the reason is what unregistering answered.
    static func repairFailure(registering: any Error, afterUnregistering unregistering: (any Error)?) -> any Error {
        let failure = registering as NSError
        guard let unregistering, failure.domain == SMAppServiceErrorDomain,
              failure.code == Int(kSMErrorAlreadyRegistered)
        else { return registering }
        return unregistering
    }

    /// True when this account is an administrator. The helper's Mach service can be reached from every account
    /// on the Mac, so the helper serves administrators only, and a standard account gets nothing from it.
    public static var isAvailableToThisAccount: Bool {
        UserAuthorization.isAdministrator(getuid())
    }

    public static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// True when any copy of Peel has registered its helper. `SMAppService` answers only for the copy that asks,
    /// so a second copy (a build folder, a download) reads "not registered" while the first copy's helper runs.
    /// launchd answers a user about a job registered on their behalf: `launchctl print` exits with 0 when the
    /// job exists and 113 when nothing registered that label.
    @concurrent
    public static func isRegisteredByAnyCopy() async -> Bool {
        guard case .success(let output) = await Subprocess.run(
            "/bin/launchctl",
            ["print", "system/\(HelperIdentity.helperIdentifier)"],
            timeout: 10
        ) else { return false }
        return output.status == 0
    }

    /// True when the helper answers over XPC with this app's protocol version and both sides pass the code
    /// signing checks.
    @concurrent
    public static func isResponding() async -> Bool {
        let version: Int? = await withHelper(fallback: nil) { helper, finish in
            helper.protocolVersion { finish($0) }
        }
        return version == HelperIdentity.protocolVersion
    }

    /// How long the helper is waited for before the request counts as unanswered.
    private static let longestWait: TimeInterval = 120

    @concurrent
    public static func moveToTrash(_ urls: [URL]) async -> TrashResult {
        var result = TrashResult()
        let trash = URL.homeDirectory.appending(path: ".Trash", directoryHint: .isDirectory)
        // The helper's own limit also bounds how many items an answer that never comes can affect.
        let limit = HelperRequest.maximumItems
        for start in stride(from: 0, to: urls.count, by: limit) {
            let batch = Array(urls[start..<min(start + limit, urls.count)])
            // Read before the move, so that if the answer is lost, moved items can be found in the Trash by identity.
            let links = Dictionary(batch.map { ($0, FileIdentity.Link.of($0)) }, uniquingKeysWith: { first, _ in first })
            let paths = batch.map { $0.path(percentEncoded: false) }
            let reply: HelperTrashReply? = await withHelper(fallback: nil) { helper, finish in
                helper.moveItemsToTrash(version: HelperIdentity.protocolVersion, atPaths: paths) { moved, failed in
                    finish(HelperTrashReply(moved: moved, failed: failed))
                }
            }
            let answered = Self.result(for: batch, reply: reply, links: links, trash: trash)
            result.trashed += answered.trashed
            result.failures += answered.failures
        }
        return result
    }

    /// Builds the result of one request from the helper's reply. The helper moves items one by one and answers
    /// once, at the end. With no answer (the helper was uninstalled midway or crashed), the items that did move
    /// are found in the Trash by identity: History is the only way back for what the helper moved, and
    /// reporting them all as failed would leave them out of History.
    static func result(for urls: [URL], reply: HelperTrashReply?, links: [URL: FileIdentity.Link?], trash: URL) -> TrashResult {
        var result = TrashResult()
        for url in urls {
            let path = url.path(percentEncoded: false)
            if let destination = reply?.moved[path] {
                let trashedURL = URL(filePath: destination)
                result.trashed.append(TrashedItem(originalURL: url, trashedURL: trashedURL, date: .now, identity: .init(ofItemAt: trashedURL)))
            } else if reply == nil, !url.isThere, let link = links[url] ?? nil, let found = TrashService.item(link, in: trash) {
                result.trashed.append(TrashedItem(originalURL: url, trashedURL: found, date: .now, identity: .init(ofItemAt: found)))
            } else {
                result.failures.append(TrashFailure(url: url, reason: .failed(reply?.failed[path] ?? Self.unavailable)))
            }
        }
        return result
    }

    /// Returns nil on success, or a failure description.
    @concurrent
    static func runDaemonCommand(_ command: DaemonCommand, label: String) async -> String? {
        await withHelper(fallback: Self.unavailable) { helper, finish in
            helper.runDaemonCommand(version: HelperIdentity.protocolVersion, command: command.rawValue, label: label) { failure in
                finish(failure)
            }
        }
    }

    /// The folder the helper keeps its ledger in: root's, so only the helper can move it.
    public static var ledgerFolder: URL {
        URL(filePath: HelperLedger.defaultFolder, directoryHint: .isDirectory)
    }

    /// What became of the helper's ledger when Peel asked for it to go to the Trash.
    public enum LedgerMove: Sendable, Equatable {
        /// There was no ledger.
        case none
        case moved
        case stayed(TrashFailure)
    }

    /// Has the helper move its own ledger to this user's Trash, since nothing else can move it.
    @concurrent
    public static func moveLedgerToTrash() async -> LedgerMove {
        let folder = ledgerFolder
        guard folder.isThere else { return .none }
        let failure: String? = await withHelper(fallback: Self.unavailable) { helper, finish in
            helper.moveLedgerToTrash(version: HelperIdentity.protocolVersion) { failure in
                finish(failure)
            }
        }
        return failure.map { .stayed(TrashFailure(url: folder, reason: .failed($0))) } ?? .moved
    }

    /// Returns nil on success, or a failure description.
    @concurrent
    static func restore(_ item: TrashedItem) async -> String? {
        await withHelper(fallback: Self.unavailable) { helper, finish in
            helper.restoreItem(
                version: HelperIdentity.protocolVersion,
                fromTrashPath: item.trashedURL.path(percentEncoded: false),
                toPath: item.originalURL.path(percentEncoded: false)
            ) { failure in
                finish(failure)
            }
        }
    }

    private static func withHelper<T: Sendable>(
        fallback: T,
        _ body: (any PeelHelperProtocol, @escaping @Sendable (T) -> Void) -> Void
    ) async -> T {
        guard let teamIdentifier = CodeSigning.currentTeamIdentifier() else { return fallback }

        let connection = NSXPCConnection(machServiceName: HelperIdentity.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: (any PeelHelperProtocol).self)
        connection.setCodeSigningRequirement(
            CodeSigning.requirement(identifier: HelperIdentity.helperIdentifier, teamIdentifier: teamIdentifier)
        )
        connection.resume()
        defer { connection.invalidate() }

        return await withCheckedContinuation { continuation in
            let once = ResumeOnce()
            let finish: @Sendable (T) -> Void = { value in
                if once.claim() {
                    continuation.resume(returning: value)
                }
            }
            // A helper that is running but never answers keeps the connection valid, so only this timer ends
            // the wait. `longestWait` outlasts any request: at most `HelperRequest.maximumItems` renames, or one
            // `launchctl` run that the helper stops after 30 seconds.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + longestWait) { finish(fallback) }
            guard let helper = connection.remoteObjectProxyWithErrorHandler({ _ in finish(fallback) }) as? any PeelHelperProtocol else {
                finish(fallback)
                return
            }
            body(helper, finish)
        }
    }
}

struct HelperTrashReply: Sendable {
    let moved: [String: String]
    let failed: [String: String]
}

private final class ResumeOnce: Sendable {
    private let hasResumed = Mutex(false)

    func claim() -> Bool {
        hasResumed.withLock { hasResumed in
            defer { hasResumed = true }
            return !hasResumed
        }
    }
}
