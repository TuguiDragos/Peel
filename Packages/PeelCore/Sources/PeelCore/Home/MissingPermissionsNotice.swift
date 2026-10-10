/// What Home asks the person to do about the required permissions that are missing. A helper that is installed but
/// doesn't answer is repaired, not set up.
public enum MissingPermissionsNotice: Sendable, Equatable {
    case setUp
    case repairTheHelper
    case setUpAndRepairTheHelper

    public init(helper: PrivilegedHelper.Standing, othersMissing: Bool) {
        self = switch (helper == .notAnswering, othersMissing) {
        case (false, _): .setUp
        case (true, false): .repairTheHelper
        case (true, true): .setUpAndRepairTheHelper
        }
    }
}
