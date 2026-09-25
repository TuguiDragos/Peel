internal import PeelPrivileged

/// Every fixed English sentence Peel's own code shows the user from outside the app's string catalog: the
/// refusals of the path rules and of the helper, a tool that timed out or was stopped, and three of PeelCore's.
/// The helper cannot know the user's language and PeelCore has no catalog, so each arrives in English, and
/// the app recognizes it here to show it translated. Anything else (a tool's own output, an error macOS
/// wrote) is not one of these.
public enum FixedSentence: CaseIterable, Sendable {
    case notAFullPath, dotInPath, controlCharacter, folderNotFound, outsideHelpersFolders, onlyAppsThere
    case notThereAnymore, alreadyThere, protectedByMacOS, irreplaceable, codeFolder, onlyLinksThere, leadsSomewhere
    case helperOutOfDate, accountNotAllowed, tooManyItems, noTrash, pathTooLong, cannotKeepRecord, notInTrash
    case notMovedByHelper, invalidRequest, configurationMissing
    case toolTimedOut, toolStopped
    case receiptMisplaced, homebrewNotInstalled, helperUnavailable

    public init?(_ message: String) {
        guard let found = Self.allCases.first(where: { $0.english == message }) else { return nil }
        self = found
    }

    /// The English exactly as it is sent.
    public var english: String {
        switch self {
        case .notAFullPath: PrivilegedPathPolicy.Rejection.notAbsolute.explanation
        case .dotInPath: PrivilegedPathPolicy.Rejection.relativeComponent.explanation
        case .controlCharacter: PrivilegedPathPolicy.Rejection.controlCharacter.explanation
        case .folderNotFound: PrivilegedPathPolicy.Rejection.unresolvableParent.explanation
        case .outsideHelpersFolders: PrivilegedPathPolicy.Rejection.outsideAllowedLocations.explanation
        case .onlyAppsThere: PrivilegedPathPolicy.Rejection.notAnApplication.explanation
        case .notThereAnymore: PrivilegedPathPolicy.Rejection.missing.explanation
        case .alreadyThere: PrivilegedPathPolicy.Rejection.alreadyExists.explanation
        case .protectedByMacOS: PrivilegedPathPolicy.Rejection.protectedByFlags.explanation
        case .irreplaceable: PrivilegedPathPolicy.Rejection.irreplaceable.explanation
        case .codeFolder: PrivilegedPathPolicy.Rejection.loadsCode.explanation
        case .onlyLinksThere: PrivilegedPathPolicy.Rejection.notALink.explanation
        case .leadsSomewhere: PrivilegedPathPolicy.Rejection.leadsSomewhere.explanation
        case .helperOutOfDate: HelperRefusal.outOfDate.rawValue
        case .accountNotAllowed: HelperRefusal.notAllowed.rawValue
        case .tooManyItems: HelperRefusal.tooManyItems.rawValue
        case .noTrash: HelperRefusal.noTrash.rawValue
        case .pathTooLong: HelperRefusal.pathTooLong.rawValue
        case .cannotKeepRecord: HelperRefusal.cannotKeepRecord.rawValue
        case .notInTrash: HelperRefusal.notInTrash.rawValue
        case .notMovedByHelper: HelperRefusal.notMovedByHelper.rawValue
        case .invalidRequest: HelperRefusal.invalidRequest.rawValue
        case .configurationMissing: HelperRefusal.missingConfiguration.rawValue
        case .toolTimedOut: Subprocess.Failure.timedOut.explanation
        case .toolStopped: Subprocess.Failure.canceled.explanation
        case .receiptMisplaced: PackageActions.misplacedReceipt
        case .homebrewNotInstalled: Homebrew.notInstalled
        case .helperUnavailable: PrivilegedHelper.unavailable
        }
    }
}
