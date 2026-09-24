import Accessibility
import PeelCore
import SwiftUI

// The summary each tool's detail pane shows before anything is chosen, which VoiceOver also reads when a scan
// ends: what the tool found, in numbers.
//
// Each sentence is one localized string with its numbers inside, so a translation can put the parts in any
// order, as Japanese or Turkish need. The sentences avoid verbs that would have to agree with a number, and the
// total comes first because `SizeTotal.text` ("Over X") is written to stand on its own.

extension SizeTotal {
    /// Adds totals together. The sum is complete only when every part is.
    init(combining totals: [SizeTotal]) {
        self.init(known: totals.reduce(0) { $0 + $1.known }, isComplete: totals.allSatisfy(\.isComplete))
    }
}

extension AppLibrary {
    var summary: AttributedString? {
        guard hasLoaded else { return nil }
        let count = apps.count
        let known = sizes.values.reduce(0, +)
        let total = SizeTotal(known: known, isComplete: sizes.count >= count)
        let size = known > 0 ? AttributedString(localized: "\(total.text) in ^[\(count) app](inflect: true).") : AttributedString(localized: "^[\(count) app](inflect: true).")
        let waiting = appsWithUpdates.count
        guard waiting > 0 else { return size }
        return size + AttributedString("\n") + AttributedString(localized: "^[\(waiting) update](inflect: true) waiting.")
    }
}

extension OrphanLibrary {
    var summary: AttributedString? {
        guard let groups = scan?.groups, !groups.isEmpty else { return nil }
        let total = SizeTotal(combining: groups.map(\.total))
        return total.known > 0
            ? AttributedString(localized: "\(total.text) in ^[\(groups.count) group](inflect: true).")
            : AttributedString(localized: "^[\(groups.count) group](inflect: true).")
    }
}

extension DeveloperLibrary {
    var summary: AttributedString? {
        guard let environments, !environments.isEmpty else { return nil }
        let total = SizeTotal(combining: environments.map(\.total))
        return total.known > 0
            ? AttributedString(localized: "\(total.text) in ^[\(environments.count) tool](inflect: true).")
            : AttributedString(localized: "^[\(environments.count) tool](inflect: true).")
    }
}

extension ProjectLibrary {
    var summary: AttributedString? {
        guard let groups, !groups.isEmpty else { return nil }
        let total = SizeTotal(combining: groups.map(\.total))
        return total.known > 0
            ? AttributedString(localized: "\(total.text) in ^[\(groups.count) project](inflect: true).")
            : AttributedString(localized: "^[\(groups.count) project](inflect: true).")
    }
}

extension SpaceLibrary {
    var summary: AttributedString? {
        guard let items = report?.items, !items.isEmpty else { return nil }
        let total = SizeTotal(items.map(\.size))
        return total.known > 0
            ? AttributedString(localized: "\(total.text) in ^[\(items.count) area](inflect: true).")
            : AttributedString(localized: "^[\(items.count) area](inflect: true).")
    }
}

extension InstallerLibrary {
    var summary: AttributedString? {
        guard let items = scan?.items, !items.isEmpty else { return nil }
        let total = SizeTotal(items.map(\.size))
        return total.known > 0
            ? AttributedString(localized: "\(total.text) in ^[\(items.count) item](inflect: true).")
            : AttributedString(localized: "^[\(items.count) item](inflect: true).")
    }
}

extension HomebrewLibrary {
    var summary: AttributedString? {
        guard let packages, !packages.isEmpty else { return nil }
        let count = AttributedString(localized: "^[\(packages.count) package](inflect: true).")
        let outdated = packages.count(where: \.isOutdated)
        guard outdated > 0 else { return count }
        return count + AttributedString("\n") + AttributedString(localized: "^[\(outdated) update](inflect: true) waiting.")
    }
}

extension PackageLibrary {
    var summary: AttributedString? {
        guard let receipts, !receipts.isEmpty else { return nil }
        return AttributedString(localized: "^[\(receipts.count) package](inflect: true).")
    }
}

extension PluginLibrary {
    var summary: AttributedString? {
        guard let plugins, !plugins.isEmpty else { return nil }
        return AttributedString(localized: "^[\(plugins.count) plug-in](inflect: true).")
    }
}

extension ExtensionLibrary {
    var summary: AttributedString? {
        guard let extensions, !extensions.isEmpty else { return nil }
        return AttributedString(localized: "^[\(extensions.count) extension](inflect: true).")
    }
}

extension BackgroundItemLibrary {
    var summary: AttributedString? {
        guard let items, !items.isEmpty else { return nil }
        return AttributedString(localized: "^[\(items.count) background item](inflect: true).")
    }
}

extension IntelLibrary {
    var summary: AttributedString? {
        guard let findings = scan?.findings, !findings.isEmpty else { return nil }
        return AttributedString(localized: "^[\(findings.count) item](inflect: true) built for Intel.")
    }
}

extension RemovalHistoryStore {
    var summary: AttributedString? {
        guard !batches.isEmpty else { return nil }
        return AttributedString(localized: "^[\(batches.count) removal](inflect: true).")
    }
}

extension View {
    /// Tells VoiceOver what a scan found when it ends, since a scan can take minutes and the list fills in
    /// silently. A stopped scan is announced as stopped.
    func announcesScan(_ isScanning: Bool, found summary: AttributedString?, wasStopped: Bool = false) -> some View {
        onChange(of: isScanning) { wasScanning, scanning in
            guard wasScanning, !scanning else { return }
            let words = wasStopped ? AttributedString(localized: "Scan stopped.") : summary ?? AttributedString(localized: "Nothing found.")
            AccessibilityNotification.Announcement(words).post()
        }
    }
}
