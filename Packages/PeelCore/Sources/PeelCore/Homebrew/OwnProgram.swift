import Darwin
import PeelPrivileged

/// The file Peel runs from right now, to tell afterward whether something put another file in its place. `brew` leaves
/// the app it runs inside open (`hosting_brew?` in its cask code), so a `brew update` that follows a tap's migration
/// replaces Peel while it runs, and `SMAppService` then answers this process that nothing of its is registered.
public struct OwnProgram: Sendable {
    private let path: String?
    private let identity: ItemIdentity?

    public init() {
        self.init(path: RunningProgram.path(of: getpid()))
    }

    init(path: String?) {
        self.path = path
        identity = path.flatMap(ItemIdentity.init(ofItemAt:))
    }

    public var isReplaced: Bool {
        guard let path else { return false }
        return ItemIdentity(ofItemAt: path) != identity
    }
}
