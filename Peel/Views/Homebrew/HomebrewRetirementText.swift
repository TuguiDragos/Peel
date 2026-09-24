import Foundation
import PeelCore
import SwiftUI

/// What Peel says about a package Homebrew has deprecated or disabled. Homebrew's own messages are in English,
/// so each reason it names is written out here in the user's language.
extension HomebrewRetirement {
    /// The format for a disable date, in UTC. Homebrew gives only a day, stored as midnight UTC, and in local
    /// time it would show as the day before in time zones behind UTC.
    private static var day: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.day().month().year()
        style.timeZone = .gmt
        return style
    }

    /// Returns the disable date if it's still to come. A past date on a package that is only deprecated says
    /// nothing about when it will be disabled.
    private func upcomingDisableDate(now: Date) -> Date? {
        disableDate.flatMap { $0 > now ? $0 : nil }
    }

    var title: Text {
        switch stage {
        case .deprecated: Text("Homebrew has deprecated this package")
        case .disabled: Text("Homebrew has disabled this package")
        }
    }

    /// The line under the package's name in the list.
    func caption(now: Date) -> Text {
        switch stage {
        case .disabled:
            if let disableDate { return Text("Disabled on \(disableDate.formatted(Self.day))") }
            return Text(LocalizedStringResource("Disabled (Homebrew)", defaultValue: "Disabled", comment: "Status under a Homebrew package's name: Homebrew has stopped offering the package."))
        case .deprecated:
            if let date = upcomingDisableDate(now: now) { return Text("Will be disabled on \(date.formatted(Self.day))") }
            return Text(LocalizedStringResource("Deprecated (Homebrew)", defaultValue: "Deprecated", comment: "Status under a Homebrew package's name: Homebrew plans to stop offering the package."))
        }
    }

    /// The explanation on the package's page: the reason, what it means for the installed package, and what
    /// Homebrew suggests instead, one paragraph each.
    func explanation(now: Date) -> Text {
        let paragraphs = [because, consequence(now: now), suggestion].compactMap(\.self)
        return paragraphs.dropFirst().reduce(paragraphs[0]) { Text("\($0)\n\n\($1)") }
    }

    private var because: Text? {
        switch reason {
        case nil: nil
        case .discontinued: Text("Its maker has discontinued it.")
        case .movedToAppStore: Text("Its maker now offers it only in the App Store.")
        case .noLongerAvailable: Text("Its maker no longer offers it for download.")
        case .noLongerMeetsCriteria: Text("It no longer meets Homebrew’s rules for casks.")
        case .unmaintained: Text("It is no longer maintained.")
        case .failsGatekeeperCheck: Text("It doesn’t pass Gatekeeper, the check macOS makes before it opens an app.")
        case .unreachable: Text("Homebrew can no longer reliably download it.")
        case .doesNotBuild: Text("It no longer builds.")
        case .noLicense: Text("It has no license.")
        case .repositoryArchived: Text("Its source repository has been archived.")
        case .repositoryRemoved: Text("Its source repository has been removed.")
        case .unsupported: Text("Its maker no longer supports it.")
        case .deprecatedUpstream: Text("Its maker has deprecated it.")
        case .versionedFormula: Text("It is an older version Homebrew kept beside the current one.")
        case .checksumMismatch: Text("Its source no longer matches what Homebrew first checked, so the maker’s repository may have been tampered with.")
        case .written(let words): Text("Homebrew gives this reason: “\(words)”")
        }
    }

    private func consequence(now: Date) -> Text {
        switch stage {
        case .disabled:
            if let disableDate {
                return Text("Homebrew stopped offering it on \(disableDate.formatted(Self.day)): it can’t be installed again and gets no more upgrades. What is installed stays until you uninstall it.")
            }
            return Text("Homebrew no longer offers it: it can’t be installed again and gets no more upgrades. What is installed stays until you uninstall it.")
        case .deprecated:
            if let date = upcomingDisableDate(now: now) {
                return Text("Homebrew still upgrades it for now, and disables it on \(date.formatted(Self.day)).")
            }
            return Text("Homebrew still upgrades it for now, and may disable it at any time.")
        }
    }

    private var suggestion: Text? {
        switch replacement {
        case nil: nil
        case .formula(let name): Text("Homebrew suggests the \(name) formula instead.")
        case .cask(let name): Text("Homebrew suggests the \(name) cask instead.")
        }
    }
}
