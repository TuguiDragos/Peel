public import Foundation

/// A package Homebrew has deprecated or disabled. Deprecation usually comes first. A disabled package can't be
/// installed again and gets no more upgrades, though what is installed stays. Read from `brew info --json=v2`,
/// whose `deprecated` and `disabled` flags already take their dates into account.
public struct HomebrewRetirement: Sendable, Hashable {
    public enum Stage: Sendable, Hashable {
        case deprecated
        case disabled
    }

    /// Why Homebrew deprecated or disabled a package: one of the reasons it declares in `deprecate_disable.rb`,
    /// shared by formulae and casks, or a sentence a maintainer wrote instead, kept as written, in English.
    public enum Reason: Sendable, Hashable {
        case discontinued
        case movedToAppStore
        case noLongerAvailable
        case noLongerMeetsCriteria
        case unmaintained
        case failsGatekeeperCheck
        case unreachable
        case doesNotBuild
        case noLicense
        case repositoryArchived
        case repositoryRemoved
        case unsupported
        case deprecatedUpstream
        case versionedFormula
        case checksumMismatch
        case written(String)

        public init(_ word: String) {
            self = switch word {
            case "discontinued": .discontinued
            case "moved_to_mas": .movedToAppStore
            case "no_longer_available": .noLongerAvailable
            case "no_longer_meets_criteria": .noLongerMeetsCriteria
            case "unmaintained": .unmaintained
            case "fails_gatekeeper_check": .failsGatekeeperCheck
            case "unreachable": .unreachable
            case "does_not_build": .doesNotBuild
            case "no_license": .noLicense
            case "repo_archived": .repositoryArchived
            case "repo_removed": .repositoryRemoved
            case "unsupported": .unsupported
            case "deprecated_upstream": .deprecatedUpstream
            case "versioned_formula": .versionedFormula
            case "checksum_mismatch": .checksumMismatch
            default: .written(word)
            }
        }
    }

    public enum Replacement: Sendable, Hashable {
        case formula(String)
        case cask(String)
    }

    public let stage: Stage
    public let reason: Reason?
    /// The day the package was or will be disabled. A deprecated package can have one too. Homebrew gives a day
    /// with no time, so it is kept as midnight UTC and shows the right day only when formatted in UTC.
    public let disableDate: Date?
    public let replacement: Replacement?

    public init(stage: Stage, reason: Reason?, disableDate: Date?, replacement: Replacement?) {
        self.stage = stage
        self.reason = reason
        self.disableDate = disableDate
        self.replacement = replacement
    }

    /// Returns nil unless the package is deprecated or disabled. A package that is both counts as disabled,
    /// since what matters is that it can't be installed anymore.
    init?(
        deprecated: Bool?, disabled: Bool?, disableDate: String?,
        deprecationReason: String?, disableReason: String?,
        deprecationReplacement: (formula: String?, cask: String?), disableReplacement: (formula: String?, cask: String?)
    ) {
        let isDisabled = disabled == true
        guard isDisabled || deprecated == true else { return nil }
        let replacement = isDisabled ? disableReplacement : deprecationReplacement
        stage = isDisabled ? .disabled : .deprecated
        reason = (isDisabled ? disableReason ?? deprecationReason : deprecationReason).map(Reason.init)
        self.disableDate = disableDate.flatMap { try? Date($0, strategy: .iso8601.year().month().day()) }
        self.replacement = replacement.formula.map(Replacement.formula) ?? replacement.cask.map(Replacement.cask)
    }
}
