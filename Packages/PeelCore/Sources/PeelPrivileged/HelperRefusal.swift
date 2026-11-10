/// The sentences the helper sends when it refuses a request, besides the path rules' `Rejection`s. It runs
/// as root and cannot know the reader's language, so it sends English, and the app recognizes each sentence
/// (`FixedSentence`) and shows it in the reader's language.
public enum HelperRefusal: String, CaseIterable, Sendable {
    case outOfDate = "Peel and its helper are from different versions. Repair the helper in Peel’s Settings."
    case notAllowed = "This account isn’t allowed to use Peel’s helper."
    /// An account that isn't an administrator asked without an administrator's approval in force.
    case notAuthorized = "An administrator didn’t allow this."
    case tooManyItems = "Too many items in one request."
    case noTrash = "There’s no Trash to move this to."
    case pathTooLong = "The path is too long."
    case cannotKeepRecord = "Peel’s helper can’t keep its record of what it moves, so nothing was moved."
    case cannotReadRecord = "Peel’s helper can’t read its record of what it moved, so nothing was put back."
    case notInTrash = "It isn’t in the Trash."
    case notInRecord = "Peel’s helper has no record of moving this from there, so it stays in the Trash. You can drag it back out in Finder."
    case invalidRequest = "The request wasn’t valid."
    case missingConfiguration = "The configuration file is missing."
    case declaredTwice = "Two files in /Library/LaunchDaemons declare this job, so Peel’s helper can’t tell which one to load. Move one of them to the Trash first."
    /// The item left its folder for the helper's own and could neither reach its place nor go back.
    case keptByTheHelper = "It couldn’t go back to its folder, so Peel’s helper keeps it and moves it to the Trash the next time the helper starts."
    /// Everything the helper moves passes through a folder of its own on the startup disk, and a rename never leaves
    /// its disk, so nothing reaches a Trash on another disk.
    case anotherDisk = "Your home folder is on a different disk from macOS, and Peel’s helper never moves anything from one disk to another. You can move it in Finder."
    /// The request's time to move ran out before the helper got to the item.
    case ranOutOfTime = "Peel’s helper ran out of time before it got to this, so it stays where it was. Try again."
}
