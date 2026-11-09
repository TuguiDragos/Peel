import AppKit

/// Tells Home's greeting that the time may have jumped past what its schedule knows: a new day, the clock or the time
/// zone set again, or the Mac awake. macOS posts each of these, a new day also on waking when it began during sleep
/// (`NSCalendar.h`), and a `TimelineView` follows only its own schedule.
@Observable
final class TimeChanges {
    static let shared = TimeChanges(center: .default, workspace: NSWorkspace.shared.notificationCenter)

    private(set) var revision = 0
    @ObservationIgnored private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    init(center: NotificationCenter, workspace: NotificationCenter) {
        let followed: [(NotificationCenter, Notification.Name)] = [
            (center, .NSCalendarDayChanged), (center, .NSSystemClockDidChange), (center, .NSSystemTimeZoneDidChange),
            (workspace, NSWorkspace.didWakeNotification),
        ]
        for (center, name) in followed {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.revision += 1 }
            }
            observers.append((center, token))
        }
    }

    isolated deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }
}
