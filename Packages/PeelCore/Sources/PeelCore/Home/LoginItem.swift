import Observation
public import ServiceManagement

/// Peel's own login item, read and changed away from the main actor, since `SMAppService` asks `smd` over XPC. The
/// switch keeps the value it was set to until macOS answers, and a read that overlaps a change shows nothing.
@MainActor
@Observable
public final class LoginItem {
    public struct Answer: Sendable {
        public var status: SMAppService.Status
        public var error: String?

        public init(status: SMAppService.Status, error: String? = nil) {
            self.status = status
            self.error = error
        }
    }

    public typealias Read = @MainActor () async -> SMAppService.Status
    public typealias Change = @MainActor (_ on: Bool) async -> Answer

    public private(set) var status: SMAppService.Status?
    /// Why the last change left the item other than asked. Nil when the status says the change took, since
    /// registering an item that is registered already throws too (`SMAppService.h`).
    public private(set) var failure: String?
    private var asked: Bool?
    private var checks = OverlappingChecks()
    private let changes = OneAtATime<Bool>()
    private let read: Read
    private let change: Change

    public init(read: @escaping Read, change: @escaping Change) {
        self.read = read
        self.change = change
    }

    public static func ofTheMainApp() -> LoginItem {
        LoginItem(read: { await status() }, change: { await set(on: $0) })
    }

    public var isOn: Bool {
        asked ?? Self.isOn(status)
    }

    /// Whether macOS has said what the item is, or the person has just set it. Until then `isOn` is no fact.
    public var isKnown: Bool { status != nil || asked != nil }

    public var needsApproval: Bool {
        status == .requiresApproval
    }

    public func refresh() async {
        let check = checks.start()
        let status = await read()
        guard checks.mayShow(check) else { return }
        self.status = status
    }

    public func set(on: Bool) {
        asked = on
        Task {
            await changes.ask(on) { [self] on, anotherWaits in
                checks.changeStarts()
                let answer = await change(on)
                checks.changeEnds()
                status = answer.status
                failure = Self.isOn(answer.status) == on ? nil : answer.error
                if !anotherWaits() {
                    asked = nil
                }
            }
        }
    }

    private static func isOn(_ status: SMAppService.Status?) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    @concurrent
    public static func status() async -> SMAppService.Status {
        SMAppService.mainApp.status
    }

    @concurrent
    private static func set(on: Bool) async -> Answer {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try await SMAppService.mainApp.unregister()
            }
        } catch {
            return Answer(status: SMAppService.mainApp.status, error: error.localizedDescription)
        }
        return Answer(status: SMAppService.mainApp.status)
    }
}
