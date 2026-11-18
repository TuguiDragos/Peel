import SwiftUI

/// What the question before an upgrade says: on the Homebrew page, that it can take long, and, for a cask, that
/// Homebrew deletes the version of the app it replaces, which History can't put back.
enum HomebrewUpgradeWarning {
    /// Where the question is asked. Only the Homebrew page shows an upgrade's progress and can stop it.
    enum Place {
        case homebrewPage
        case appPage
    }

    static let takesLong: LocalizedStringResource = "This can take a long time, since Homebrew builds some packages on this Mac. Its progress shows on this page as it works, and you can stop it there."
    static let deletesTheApp: LocalizedStringResource = "Homebrew deletes each app version it replaces, which History cannot put back."

    static func sentences(deletesAnApp: Bool, on place: Place) -> [LocalizedStringResource] {
        (place == .homebrewPage ? [takesLong] : []) + (deletesAnApp ? [deletesTheApp] : [])
    }

    static func text(deletesAnApp: Bool, on place: Place = .homebrewPage) -> Text {
        let sentences = sentences(deletesAnApp: deletesAnApp, on: place).map { Text($0) }
        guard let first = sentences.first else { return Text(verbatim: "") }
        return sentences.dropFirst().reduce(first) { Text("\($0)\n\n\($1)") }
    }
}
