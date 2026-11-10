/// The folders commands are run from by name, by who puts commands there, as paths from the root or the home. An
/// uninstall and Orphaned Files look in every one for links into an app, Intel Software and This Belongs To read the
/// commands in all but Homebrew's on Apple silicon, and the helper takes a link that leads nowhere from `usrLocal`'s
/// and `macPorts`'.
public enum CommandFolders {
    /// `/usr/local`, Homebrew's prefix on an Intel Mac, where an app or a person also links a tool.
    public static let usrLocal = ["usr/local/bin", "usr/local/sbin"]
    /// Homebrew's prefix on Apple silicon, where it links its formulae's commands and a cask's `binary` (Cask
    /// Cookbook).
    public static let homebrew = ["opt/homebrew/bin", "opt/homebrew/sbin"]
    /// MacPorts' prefix.
    public static let macPorts = ["opt/local/bin", "opt/local/sbin"]
    /// The home's, which a person puts on the path.
    public static let home = ["bin", ".local/bin"]
}
