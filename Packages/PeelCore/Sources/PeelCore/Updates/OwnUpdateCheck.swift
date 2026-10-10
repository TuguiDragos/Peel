/// When Peel may ask about its own updates: whenever the person asks, and on its own only while Check for app updates
/// is on, since Settings promises that with it off Peel contacts nothing on its own.
public enum OwnUpdateCheck {
    public static func mayAsk(askedByThePerson: Bool, checksForAppUpdates: Bool) -> Bool {
        askedByThePerson || checksForAppUpdates
    }
}
