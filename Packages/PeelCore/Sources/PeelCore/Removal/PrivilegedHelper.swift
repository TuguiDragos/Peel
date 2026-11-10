public import Foundation
import PeelPrivileged
import ServiceManagement
import Synchronization

public enum PrivilegedHelper {
    static let unavailable = "Peel’s helper isn’t answering. Repair it in Peel’s Settings."
    /// What is said of an item a helper's answer leaves out, which is no sign the helper didn't answer.
    static let saidNothing = "Peel’s helper said nothing about this one, so Peel doesn’t know what became of it."
    /// What is said of an item still in its place when the helper's answer never came: a helper held up in a move
    /// may still take it, and a line written before the request brings it into History once Peel opens again.
    static let mayStillMove = "Peel’s helper didn’t answer in time, so whether it moved this isn’t known. If it did, History lists it the next time Peel opens."

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

        /// Another account uses a helper that works, with an administrator's approval for each action, and anything
        /// else needs an administrator: only one installs, approves, or repairs the helper.
        public init(status: Status, isAdministrator: Bool, isResponding: Bool?) {
            if status == .enabled, isResponding != false {
                self = .ready
                return
            }
            guard isAdministrator else {
                self = .notThisAccount
                return
            }
            self = switch status {
            case .enabled: .notAnswering
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

    /// `status`, read away from the caller's actor: `SMAppService` asks `smd` over XPC, which takes milliseconds.
    @concurrent
    public static func currentStatus() async -> Status {
        status
    }

    @concurrent
    public static func register() async throws {
        try await register(service.register, status: { status }, pause: { try await Task.sleep(for: .seconds(4)) })
    }

    static let registrationAttempts = 4

    /// macOS refuses (`EPERM`) to register a service it has just unregistered until Background Task Management has
    /// saved the change, a few seconds after the last one, and a refusal counts as a change. So a refusal is tried
    /// again after a longer pause, while the helper reads as not registered; one turned off in Login Items waits.
    static func register(
        _ attempt: () throws -> Void,
        status: () -> Status,
        pause: () async throws -> Void
    ) async throws {
        for remaining in (0..<registrationAttempts).reversed() {
            do {
                return try attempt()
            } catch let error as NSError
                where remaining > 0 && error.domain == SMAppServiceErrorDomain && error.code == Int(EPERM)
                && status() == .notRegistered {
                try await pause()
            }
        }
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
            try await register()
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

    /// True when this account is an administrator, whom the helper serves as one. Any other account needs an
    /// administrator's approval for each action (`AdministratorConsent`).
    public static var isAdministrator: Bool {
        UserAuthorization.isAdministrator(getuid())
    }

    /// `isAdministrator`, asked away from the caller's actor: the answer comes from opendirectoryd.
    @concurrent
    public static func isAdministratorNow() async -> Bool {
        isAdministrator
    }

    /// The words macOS's window shows under its own when Peel asks an administrator, in the reader's language, which
    /// the app sets: PeelCore has no catalog.
    public static var consentPrompt: String? {
        get { prompt.withLock { $0 } }
        set { prompt.withLock { $0 = newValue } }
    }

    private static let prompt = Mutex<String?>(nil)

    /// The approval the requests of the action under way carry.
    @TaskLocal static var consent: AdministratorConsent?

    /// Runs `body` with one approval for all of its requests to the helper, asked for at the first that needs one and
    /// destroyed when `body` ends, or within an action already under way with that action's.
    public static func withOneConsent<T, E: Error>(_ body: () async throws(E) -> T) async throws(E) -> T {
        try await withOneConsent(AdministratorConsent(), body)
    }

    static func withOneConsent<T, E: Error>(
        _ made: @autoclosure () -> AdministratorConsent, _ body: () async throws(E) -> T
    ) async throws(E) -> T {
        if consent != nil { return try await body() }
        let consent = made()
        let result: Result<T, E> = await $consent.withValue(consent) {
            do throws(E) {
                return .success(try await body())
            } catch {
                return .failure(error)
            }
        }
        await consent.end()
        return try result.get()
    }

    /// Runs `change` only while this account is an administrator, asked again now: macOS lets any account unregister
    /// the helper, which serves every administrator. Answers whether it ran.
    @discardableResult
    public static func changeAsAnAdministrator(
        _ change: () async throws -> Void,
        isAdministrator: () async -> Bool = { await isAdministratorNow() }
    ) async throws -> Bool {
        guard await isAdministrator() else { return false }
        try await change()
        return true
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
        await isResponding(connecting: helperConnection)
    }

    static func isResponding(
        connecting connect: @escaping @Sendable () -> NSXPCConnection?,
        waitingAtMost wait: TimeInterval = answerWait,
        runningHelper: @escaping @Sendable (Date, TimeInterval) async -> pid_t? = {
            await runningHelper(startedBefore: $0, within: $1)
        },
        untilEnded: @escaping @Sendable (pid_t, TimeInterval) async -> Bool = { await ProcessEnds.ends($0, within: $1) }
    ) async -> Bool {
        // The steps between two questions run at the timers' quality too: a task that asks at a lower one resumes
        // behind Peel's busy threads, and the wait it spent there would be taken from a helper that answered.
        await Task.detached(priority: .userInitiated) {
            let deadline = ContinuousClock.now.advanced(by: .seconds(wait))
            let left = { ContinuousClock.now.duration(to: deadline) / .seconds(1) }
            let asked = Date.now
            let first = await askVersion(connecting: connect, waitingAtMost: wait)
            if first.value == HelperIdentity.protocolVersion { return true }
            guard first.value != nil || first.wasRejected else { return false }
            // A helper of another version, or one XPC turns away because an update deleted its program, is one the
            // update left running: it leaves as soon as no connection is open (`HelperLifetime`), and launchd then
            // starts the one this copy carries. Another copy's helper keeps running.
            var process = first.process
            if process == nil { process = await runningHelper(asked, left()) }
            if let process {
                guard await untilEnded(process, left()) else { return false }
            }
            return await askVersion(connecting: connect, waitingAtMost: left()).value == HelperIdentity.protocolVersion
        }.value
    }

    /// The process launchd runs the helper in, if it already ran when Peel asked at `date`: XPC names no process whose
    /// answer it turned away, launchd tells any account about a job of the system domain, and a process started later
    /// can't have answered, being the helper this copy carries, started for another question.
    @concurrent
    static func runningHelper(startedBefore date: Date, within limit: TimeInterval) async -> pid_t? {
        guard limit > 0, case .success(let output) = await Subprocess.run(
            "/bin/launchctl", ["print", "system/\(HelperIdentity.helperIdentifier)"], timeout: limit
        ) else { return nil }
        return process(in: Launchctl.answer(status: output.status, output: output.text), startedBefore: date)
    }

    static func process(
        in answer: Launchctl.Answer, startedBefore date: Date, startTime: (pid_t) -> Date? = ProcessEnds.startTime
    ) -> pid_t? {
        guard case .details(let details) = answer, let process = details.pid, let started = startTime(process),
              started < date
        else { return nil }
        return process
    }

    private static func askVersion(
        connecting connect: @escaping @Sendable () -> NSXPCConnection?,
        waitingAtMost wait: TimeInterval
    ) async -> Reply<Int?> {
        await answer(connecting: connect, waitingAtMost: wait, fallback: nil) { helper, finish in
            helper.protocolVersion { finish($0) }
        }
    }

    /// How long a request is waited for before it counts as unanswered: longer than the helper works on one request's
    /// items (`HelperRequest.timeToMove`), or than one `launchctl` run, which the helper stops after 30 seconds.
    static let requestWait: TimeInterval = 120

    /// How long the helper is given to say it is there: launchd starts a job at most once every 10 seconds
    /// (`man launchd.plist`, ThrottleInterval), and the helper itself starts in a fraction of a second.
    static let answerWait: TimeInterval = 15

    /// At utility quality these timers would wait behind any utility work queued before them.
    static let timers = DispatchQueue.global(qos: .userInitiated)

    /// Moves `urls` to the Trash in one request, so at most `HelperRequest.maximumItems` of them: the helper refuses
    /// more.
    @concurrent
    public static func moveToTrash(_ urls: [URL]) async -> TrashResult {
        let trash = URL.homeDirectory.appending(path: ".Trash", directoryHint: .isDirectory)
        // Read before the move, so that if the answer is lost, moved items can be found in the Trash by identity.
        let links = Dictionary(urls.map { ($0, FileIdentity.Link.of($0)) }, uniquingKeysWith: { first, _ in first })
        let paths = urls.map { $0.path(percentEncoded: false) }
        let notAuthorized = Dictionary(paths.map { ($0, HelperRefusal.notAuthorized.rawValue) }) { first, _ in first }
        let refused = HelperTrashReply(moved: [:], failed: notAuthorized)
        let reply: HelperTrashReply? = await withHelper(fallback: nil, refused: refused) { helper, approval, finish in
            helper.moveItemsToTrash(
                version: HelperIdentity.protocolVersion, approval: approval, atPaths: paths
            ) { moved, failed in
                finish(HelperTrashReply(moved: moved, failed: failed))
            }
        }
        return Self.result(for: urls, reply: reply, links: links, trash: trash)
    }

    /// Builds the result of one request from the helper's reply. The helper moves items one by one and answers
    /// once, at the end. With no answer (the helper was uninstalled midway or crashed), the items that did move
    /// are found in the Trash by identity: History is the only way back for what the helper moved, and
    /// reporting them all as failed would leave them out of History.
    static func result(
        for urls: [URL],
        reply: HelperTrashReply?,
        links: [URL: FileIdentity.Link?],
        trash: URL
    ) -> TrashResult {
        var result = TrashResult()
        for url in urls {
            let path = url.path(percentEncoded: false)
            if let destination = reply?.moved[path] {
                let trashedURL = URL(filePath: destination)
                result.trashed.append(
                    TrashedItem(
                        originalURL: url,
                        trashedURL: trashedURL,
                        date: .now,
                        identity: .init(ofItemAt: trashedURL)
                    )
                )
            } else if reply == nil, !url.isThere, let link = links[url] ?? nil,
                      let found = TrashService.item(link, in: trash)
                          ?? TrashService.item(link, named: url.lastPathComponent, in: trash) {
                result.trashed.append(
                    TrashedItem(originalURL: url, trashedURL: found, date: .now, identity: .init(ofItemAt: found))
                )
            } else if (links[url] ?? nil) == nil, url.isMissing {
                // Nothing was there when the request went, nor is now: neither moved nor a failure.
                continue
            } else {
                let reason = reply.map { $0.failed[path] ?? Self.saidNothing } ?? Self.mayStillMove
                result.failures.append(TrashFailure(url: url, reason: .failed(reason)))
            }
        }
        return result
    }

    /// Returns nil on success, or a failure description.
    @concurrent
    static func runDaemonCommand(_ command: DaemonCommand, label: String) async -> String? {
        await withHelper(fallback: Self.unavailable, refused: HelperRefusal.notAuthorized.rawValue) {
            helper, approval, finish in
            helper.runDaemonCommand(
                version: HelperIdentity.protocolVersion,
                approval: approval,
                command: command.rawValue,
                label: label
            ) { failure in
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
        // Only an administrator removes Peel, and the helper serves one with no approval.
        let failure: String? = await request(
            connecting: helperConnection, fallback: Self.unavailable, refused: Self.unavailable, approval: { Data() }
        ) { helper, _, finish in
            helper.moveLedgerToTrash(version: HelperIdentity.protocolVersion) { failure in
                finish(failure)
            }
        }
        return failure.map { .stayed(TrashFailure(url: folder, reason: .failed($0))) } ?? .moved
    }

    /// Returns nil on success, or a failure description.
    @concurrent
    static func restore(_ item: TrashedItem) async -> String? {
        await withHelper(fallback: Self.unavailable, refused: HelperRefusal.notAuthorized.rawValue) {
            helper, approval, finish in
            helper.restoreItem(
                version: HelperIdentity.protocolVersion,
                approval: approval,
                fromTrashPath: item.trashedURL.path(percentEncoded: false),
                toPath: item.originalURL.path(percentEncoded: false)
            ) { failure in
                finish(failure)
            }
        }
    }

    /// The helper's interface as Peel calls it. NSXPC checks the classes of a reply where it is decoded, which is
    /// here, so the two dictionaries the trash method answers with are held to strings on this side: anything else
    /// would stop Peel when Swift reads them.
    static func remoteInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: (any PeelHelperProtocol).self)
        let trash = #selector((any PeelHelperProtocol).moveItemsToTrash(version:approval:atPaths:withReply:))
        let strings = NSSet(array: [NSDictionary.self, NSString.self]) as? Set<AnyHashable> ?? []
        for index in 0...1 {
            interface.setClasses(strings, for: trash, argumentIndex: index, ofReply: true)
        }
        return interface
    }

    /// Sends a request that changes something with the approval of the action under way, and answers `refused` when no
    /// administrator gave one.
    private static func withHelper<T: Sendable>(
        fallback: T,
        refused: T,
        _ body: @escaping @Sendable (any PeelHelperProtocol, Data, @escaping @Sendable (T) -> Void) -> Void
    ) async -> T {
        await withOneConsent {
            await request(
                connecting: helperConnection, fallback: fallback, refused: refused,
                approval: { await consent?.approval() }, body
            )
        }
    }

    /// Sends a request only once the helper has answered, within its own short wait, on a connection of its own: a
    /// helper launchd keeps but cannot start never answers, and the request would wait the longest any request may.
    /// The approval is asked for only then, so nobody is asked for what can't be done.
    static func request<T: Sendable>(
        connecting connect: @escaping @Sendable () -> NSXPCConnection?,
        answerWait wait: TimeInterval = answerWait,
        fallback: T,
        refused: T,
        approval: () async -> Data?,
        _ body: @escaping @Sendable (any PeelHelperProtocol, Data, @escaping @Sendable (T) -> Void) -> Void
    ) async -> T {
        guard await isResponding(connecting: connect, waitingAtMost: wait) else { return fallback }
        guard let approval = await approval() else { return refused }
        return await ask(connecting: connect, waitingAtMost: requestWait, fallback: fallback) { helper, finish in
            body(helper, approval, finish)
        }
    }

    /// A connection that takes only the helper's own code, or nil when Peel has no team to require.
    private static func helperConnection() -> NSXPCConnection? {
        guard let teamIdentifier = CodeSigning.currentTeamIdentifier() else { return nil }
        let connection = NSXPCConnection(machServiceName: HelperIdentity.machServiceName, options: .privileged)
        connection.setCodeSigningRequirement(
            CodeSigning.requirement(identifier: HelperIdentity.helperIdentifier, teamIdentifier: teamIdentifier)
        )
        return connection
    }

    static func ask<T: Sendable>(
        connecting connect: @escaping @Sendable () -> NSXPCConnection?,
        waitingAtMost wait: TimeInterval,
        fallback: T,
        _ body: @escaping @Sendable (any PeelHelperProtocol, @escaping @Sendable (T) -> Void) -> Void
    ) async -> T {
        await answer(connecting: connect, waitingAtMost: wait, fallback: fallback, body).value
    }

    private struct Reply<Value: Sendable>: Sendable {
        let value: Value
        /// The process that answered, which XPC names once it has accepted a message from it.
        let process: pid_t?
        /// Whether XPC turned the answer away, its sender not meeting this copy's requirement for the helper.
        let wasRejected: Bool
    }

    private static func answer<T: Sendable>(
        connecting connect: @escaping @Sendable () -> NSXPCConnection?,
        waitingAtMost wait: TimeInterval,
        fallback: T,
        _ body: @escaping @Sendable (any PeelHelperProtocol, @escaping @Sendable (T) -> Void) -> Void
    ) async -> Reply<T> {
        // XPC delivers a reply at the quality its message went out with, and never while Peel keeps every thread at
        // that quality busy, so the message goes out at the timer's quality, whatever the task that asks.
        await Task.detached(priority: .userInitiated) {
            guard let connection = connect() else { return Reply(value: fallback, process: nil, wasRejected: false) }
            connection.remoteObjectInterface = remoteInterface()
            connection.resume()
            defer { connection.invalidate() }

            let (value, wasRejected) = await withCheckedContinuation { continuation in
                let once = ResumeOnce()
                let finish: @Sendable (T, Bool) -> Void = { value, wasRejected in
                    if once.claim() {
                        continuation.resume(returning: (value, wasRejected))
                    }
                }
                // A helper that is running but never answers keeps the connection valid, and so does one launchd
                // keeps and cannot start, so only this timer ends the wait.
                timers.asyncAfter(deadline: .now() + wait) { finish(fallback, false) }
                guard
                    let helper = connection.remoteObjectProxyWithErrorHandler({ error in
                        let error = error as NSError
                        finish(fallback, error.domain == NSCocoaErrorDomain
                            && error.code == NSXPCConnectionCodeSigningRequirementFailure)
                    }) as? any PeelHelperProtocol
                else {
                    finish(fallback, false)
                    return
                }
                body(helper) { finish($0, false) }
            }
            let process = connection.processIdentifier
            return Reply(value: value, process: process > 0 ? process : nil, wasRejected: wasRejected)
        }.value
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
