import PeelCore
import SwiftUI

extension FixedSentence {
    /// Here rather than in PeelCore, which has no catalog of its own, so the words follow the reader's language.
    var words: LocalizedStringResource {
        switch self {
        case .notAFullPath: "That isn’t a full path."
        case .dotInPath: "The path has a . or .. in it."
        case .controlCharacter: "The path holds a character no real name has."
        case .folderNotFound: "The folder it’s in couldn’t be found."
        case .tooManyOpenFolders: "Peel’s helper had too many folders open at once. Try again."
        case .outsideHelpersFolders: "It is outside the folders Peel’s helper may touch."
        case .onlyAppsThere: "Peel removes only apps from that folder."
        case .partOfAnotherApp: "It is part of another app, and Peel removes only whole apps from that folder."
        case .notThereAnymore: "It isn’t there anymore."
        case .alreadyThere: "Something is there already."
        case .protectedByMacOS: "macOS marks it as protected."
        case .irreplaceable: "It holds something nothing could bring back, so Peel never moves it."
        case .codeFolder: "It could have changed while it was in the Trash, and code is loaded from that folder, so Peel’s helper puts back only what is root’s alone. You can drag it back out in Finder."
        case .onlyLinksThere: "Peel removes only links from that folder."
        case .leadsSomewhere: "It is a link that still leads to something on this Mac, and from that folder the Peel helper removes only links that lead nowhere."
        case .onlyGoneProgramsThere: "From that folder, Peel removes only what starts a program that is no longer there."
        case .helperOutOfDate: "Peel and its helper are from different versions. Repair the helper in Settings > Helper."
        case .accountNotAllowed: "This account isn’t allowed to use Peel’s helper."
        case .notAuthorized: "An administrator didn’t allow this."
        case .tooManyItems: "Too many items in one request."
        case .noTrash: "There’s no Trash to move this to."
        case .pathTooLong: "The path is too long."
        case .cannotKeepRecord: "Peel’s helper can’t keep its record of what it moves, so nothing was moved."
        case .cannotReadRecord: "Peel’s helper can’t read its record of what it moved, so nothing was put back."
        case .notInTrash: "It isn’t in the Trash."
        case .notInHelpersRecord: "Peel’s helper has no record of moving this from there, so it stays in the Trash. You can drag it back out in Finder."
        case .invalidRequest: "The request wasn’t valid."
        case .configurationMissing: "The configuration file is missing."
        case .declaredTwice: "Two files in /Library/LaunchDaemons declare this job, so the Peel helper cannot tell which one to load. Move one of them to the Trash first."
        case .keptByTheHelper: "It could not go back to its folder, so the Peel helper keeps it and moves it to the Trash the next time the helper starts."
        case .anotherDisk: "Your home folder is on a different disk from macOS, and the Peel helper never moves anything from one disk to another. You can move it in Finder."
        case .ranOutOfTime: "The Peel helper ran out of time before it got to this, so it stays where it was. Try again."
        case .helperMayStillMove: "The Peel helper did not answer in time, so whether it moved this is not known. If it did, History lists it the next time Peel opens."
        case .toolTimedOut: "The command did not answer in time, so Peel ended it."
        case .toolStopped: "Stopped before it finished."
        case .notOnItsOwn: "Peel did not run it, since macOS could not keep it from using the permissions Peel has."
        case .receiptMisplaced: "The receipt isn’t where macOS keeps receipts."
        case .receiptForgotten: "It was already forgotten."
        case .homebrewNotInstalled: "Homebrew isn’t installed."
        case .helperUnavailable: "The Peel helper is not answering. Repair it in Settings > Helper."
        case .helperSaidNothing: "The Peel helper said nothing about this one, so Peel does not know what became of it."
        case .helperLeftItBehind: "The Peel helper could not take this with it. To remove it, choose Go > Go to Folder in Finder, enter the folder it is in, and drag it to the Trash, which asks for an administrator."
        case .homebrewElsewhere: "Peel upgrades and uninstalls only with a Homebrew where Homebrew installs itself."
        }
    }

    /// What PeelCore or the helper sent, in the reader's language when it is one of these, as it came otherwise. A
    /// transcript that ends with one on a line of its own, as a run Peel stopped does, has that line translated.
    static func translated(_ message: String, in bundle: Bundle? = nil) -> String {
        if let sentence = FixedSentence(message) { return sentence.words.resolved(in: bundle) }
        var lines = message.trimmingCharacters(in: .newlines).components(separatedBy: "\n")
        guard lines.count > 1, let last = lines.last, let sentence = FixedSentence(last) else { return message }
        lines[lines.count - 1] = sentence.words.resolved(in: bundle)
        return lines.joined(separator: "\n")
    }
}

extension LocalizedStringResource {
    /// The words as Foundation resolves them, or from `bundle` by their key: only for a sentence with no arguments.
    func resolved(in bundle: Bundle?) -> String {
        guard let bundle else { return String(localized: self) }
        return String(localized: String.LocalizationValue(key), table: table, bundle: bundle, locale: locale)
    }
}
