/// The sentences the helper sends when it refuses a request, besides the path rules' `Rejection`s. It runs
/// as root and cannot know the reader's language, so it sends English, and the app recognizes each sentence
/// (`FixedSentence`) and shows it in the reader's language.
public enum HelperRefusal: String, CaseIterable, Sendable {
    case outOfDate = "Peel’s helper is out of date. Reinstall it in Settings."
    case notAllowed = "This account isn’t allowed to use Peel’s helper."
    case tooManyItems = "Too many items in one request."
    case noTrash = "There’s no Trash to move this to."
    case pathTooLong = "The path is too long."
    case cannotKeepRecord = "Peel’s helper can’t keep its record of what it moves, so nothing was moved."
    case notInTrash = "It isn’t in the Trash."
    case notMovedByHelper = "Peel’s helper didn’t move this from there, so it stays in the Trash. You can drag it back out in Finder."
    case invalidRequest = "The request wasn’t valid."
    case missingConfiguration = "The configuration file is missing."
}
