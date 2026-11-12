/// A command Peel gives to run in Terminal. One that runs something with `sudo` needs an administrator, since only one
/// can use `sudo` (Apple, Terminal User Guide, "Enter administrator commands in Terminal on Mac").
public enum AdministratorCommand {
    /// Whether this account has to ask an administrator to run `command`: it runs something with `sudo`, and this
    /// account isn't an administrator. `isAdministrator` is passed in, since opendirectoryd answers it and a page
    /// shouldn't wait for that each time it draws.
    public static func needsAnAdministrator(_ command: String, isAdministrator: Bool) -> Bool {
        !isAdministrator && command.split(whereSeparator: { " &;|()".contains($0) }).contains("sudo")
    }
}
