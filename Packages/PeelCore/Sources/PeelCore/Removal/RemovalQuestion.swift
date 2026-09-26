public import Foundation
public import Observation

/// A page's removal, from the question that asks about it to its end, held by the page's model.
///
/// What the question asks about is frozen when it appears, and the move takes exactly that. The question stands for
/// what it showed, so a selection that changes under it closes it. One removal runs at a time, and it counts as
/// running from the moment it is confirmed until the page has recorded it and scanned again. A scan the page asks
/// for meanwhile waits: it runs once the question is closed, and the scan that ends a removal covers one asked for
/// during it.
@MainActor
@Observable
public final class RemovalQuestion {
    /// Whether the question is up. The page shows it from this, and closing it sets this back.
    public var isAsking = false
    /// What the question asks about, as it was when it appeared.
    public private(set) var request: RemovalRequest?
    public private(set) var isRemoving = false
    @ObservationIgnored private var isScanWaiting = false

    public init() {}

    public func ask(_ request: RemovalRequest) {
        self.request = request
        isAsking = true
    }

    /// Closes the question once the selection is no longer what it asks about.
    public func selectionChanged(to selected: Set<URL>) {
        if isAsking, !isRemoving, selected != request?.urls {
            isAsking = false
        }
    }

    /// Starts the removal the question asked about, or answers nil while one is running.
    public func start() -> RemovalRequest? {
        guard !isRemoving, let request else { return nil }
        isRemoving = true
        return request
    }

    /// Ends the removal once it has moved, recorded and scanned again.
    public func finish() {
        isRemoving = false
        isScanWaiting = false
    }

    /// True when a scan the page asks for may run now. Otherwise it waits for the question to close.
    public func mayScan() -> Bool {
        guard !isAsking, !isRemoving else {
            isScanWaiting = true
            return false
        }
        isScanWaiting = false
        return true
    }

    /// True when a scan waited for the question, which has closed without starting a removal.
    public var hasWaitingScan: Bool {
        isScanWaiting && !isAsking && !isRemoving
    }
}
