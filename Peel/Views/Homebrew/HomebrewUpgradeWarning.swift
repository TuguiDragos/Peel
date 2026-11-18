import SwiftUI

/// What the question before an upgrade says: that it can take long, and, for a cask, that Homebrew deletes the version
/// of the app it replaces, which History can't put back.
enum HomebrewUpgradeWarning {
    static func text(deletesAnApp: Bool) -> Text {
        let long = Text("This can take a long time, since Homebrew builds some packages on this Mac. Its progress shows on this page as it works, and you can stop it there.")
        guard deletesAnApp else { return long }
        return Text("\(long)\n\n\(Text("Homebrew deletes each app version it replaces, which History cannot put back."))")
    }
}
