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
        try? await service.unregister()
        try service.register()
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

    /// The most items one request carries, which limits how many items an answer that never comes can affect.
    private static let itemsInARequest = 100

    @concurrent
    public static func moveToTrash(_ urls: [URL]) async -> TrashResult {
        var result = TrashResult()
        let trash = URL.homeDirectory.appending(path: ".Trash", directoryHint: .isDirectory)
        for start in stride(from: 0, to: urls.count, by: itemsInARequest) {
            let batch = Array(urls[start..<min(start + itemsInARequest, urls.count)])
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
                result.trashed.append(TrashedItem(originalURL: url, trashedURL: URL(filePath: destination), date: .now))
            } else if reply == nil, !url.isThere, let link = links[url] ?? nil, let found = TrashService.item(link, in: trash) {
                result.trashed.append(TrashedItem(originalURL: url, trashedURL: found, date: .now))
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
            // the wait. `longestWait` outlasts any request: at most `itemsInARequest` renames, or one `launchctl`
            // run that the helper stops after 30 seconds.
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
