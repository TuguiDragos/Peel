/// What Home asks the person to do about the required permissions that are missing. A helper that is installed but
/// doesn't answer is repaired, not set up, and one another copy of Peel installed is that copy's to change.
public enum MissingPermissionsNotice: Sendable, Equatable {
    case setUp
    case repairTheHelper
    case setUpAndRepairTheHelper
    case helperOfAnotherCopy
    case setUpWithHelperOfAnotherCopy

    public init(helper: PrivilegedHelper.Standing, othersMissing: Bool, helperBelongsToAnotherCopy: Bool = false) {
        if helper == .notInstalled, helperBelongsToAnotherCopy {
            self = othersMissing ? .setUpWithHelperOfAnotherCopy : .helperOfAnotherCopy
            return
        }
        self = switch (helper == .notAnswering, othersMissing) {
        case (false, _): .setUp
        case (true, false): .repairTheHelper
        case (true, true): .setUpAndRepairTheHelper
        }
    }
}
