public import UserNotifications

/// How a notice of Peel's is shown. It always goes to Notification Center, so the outcome of work that ended on a
/// page the person has left can still be read, and it is a banner only while Peel is not in front.
public enum NotificationPresentation {
    public static func options(whilePeelIsActive isActive: Bool) -> UNNotificationPresentationOptions {
        isActive ? [.list] : [.banner, .list]
    }
}
