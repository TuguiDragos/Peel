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
        case .outsideHelpersFolders: "It is outside the folders Peel’s helper may touch."
        case .onlyAppsThere: "Peel removes only apps from that folder."
        case .notThereAnymore: "It isn’t there anymore."
        case .alreadyThere: "Something is there already."
        case .protectedByMacOS: "macOS marks it as protected."
        case .irreplaceable: "It holds something nothing could bring back, so Peel never moves it."
        case .codeFolder: "Code is loaded from that folder, so only what Peel’s helper took from it can go back."
        case .helperOutOfDate: "Peel’s helper is out of date. Reinstall it in Settings."
        case .accountNotAllowed: "This account isn’t allowed to use Peel’s helper."
        case .tooManyItems: "Too many items in one request."
        case .noTrash: "There’s no Trash to move this to."
        case .pathTooLong: "The path is too long."
        case .cannotKeepRecord: "Peel’s helper can’t keep its record of what it moves, so nothing was moved."
        case .notInTrash: "It isn’t in the Trash."
        case .notMovedByHelper: "Peel’s helper didn’t move this from there, so it stays in the Trash. You can drag it back out in Finder."
        case .invalidRequest: "The request wasn’t valid."
        case .configurationMissing: "The configuration file is missing."
        case .toolTimedOut: "The tool didn’t answer in time, so it was stopped."
        case .toolStopped: "Stopped before it finished."
        case .receiptMisplaced: "The receipt isn’t where macOS keeps receipts."
        case .homebrewNotInstalled: "Homebrew isn’t installed."
        case .helperUnavailable: "Peel’s helper isn’t available."
        }
    }

    /// What PeelCore or the helper sent, in the reader's language when it is one of these, as it came otherwise.
    static func translated(_ message: String) -> String {
        FixedSentence(message).map { String(localized: $0.words) } ?? message
    }
}

#if DEBUG
extension FixedSentence {
    /// A sentence is known by its English, so the words here have to read exactly as what is sent. The key is
    /// compared rather than the text it resolves to, which a pseudolanguage rewrites.
    static func checkWords() {
        for sentence in allCases {
            assert(sentence.words.key == sentence.english, "the words for \(sentence) no longer read as what is sent")
        }
    }
}
#endif
