import Accessibility
import PeelCore
import SwiftUI

// What each tool found: the summary its pane shows, and what VoiceOver reads when a scan ends.
//
// Each sentence is one localized string with its numbers inside, so a translation can put the parts in any
// order, as Japanese or Turkish need. The sentences avoid verbs that would have to agree with a number, and the
// total comes first because `SizeTotal.text` ("Over X") is written to stand on its own.

extension Tool {
    /// What the tool found, as its pane says it and Home repeats it, or nil for a tool with no such sentence.
    func sentence(for looked: Looked) -> AttributedString? {
        let count = looked.count
        let total = looked.size.flatMap { $0.known > 0 ? $0.text : nil }
        switch self {
        case .applications, .homebrew:
            return AttributedString(localized: "^[\(count) update](inflect: true) waiting.")
        case .orphans, .duplicates:
            return total.map { AttributedString(localized: "\($0) in ^[\(count) group](inflect: true).") }
                ?? AttributedString(localized: "^[\(count) group](inflect: true).")
        case .developer:
            return total.map { AttributedString(localized: "\($0) in ^[\(count) tool](inflect: true).") }
                ?? AttributedString(localized: "^[\(count) tool](inflect: true).")
        case .projects:
            return total.map { AttributedString(localized: "\($0) in ^[\(count) project](inflect: true).") }
                ?? AttributedString(localized: "^[\(count) project](inflect: true).")
        case .space:
            return total.map { AttributedString(localized: "\($0) in ^[\(count) area](inflect: true).") }
                ?? AttributedString(localized: "^[\(count) area](inflect: true).")
        case .installers, .cloud, .fileSearch:
            return total.map { AttributedString(localized: "\($0) in ^[\(count) item](inflect: true).") }
                ?? AttributedString(localized: "^[\(count) item](inflect: true).")
        case .intel:
            return AttributedString(localized: "^[\(count) item](inflect: true) built for Intel.")
        case .home, .packages, .backgroundItems, .extensions, .plugins, .tweaks, .terminal, .history:
            return nil
        }
    }

    /// What the tool found in a word or two, for the menu bar panel's Found list: the size when it is known, and
    /// otherwise the count.
    func figure(for looked: Looked) -> String? {
        if let size = looked.size, size.known > 0 { return size.text }
        let count = looked.count
        let words: AttributedString? = switch self {
        case .applications, .homebrew: AttributedString(localized: "^[\(count) update](inflect: true)")
        case .orphans, .duplicates: AttributedString(localized: "^[\(count) group](inflect: true)")
        case .developer: AttributedString(localized: "^[\(count) tool](inflect: true)")
        case .projects: AttributedString(localized: "^[\(count) project](inflect: true)")
        case .space: AttributedString(localized: "^[\(count) area](inflect: true)")
        case .installers, .cloud, .fileSearch, .intel: AttributedString(localized: "^[\(count) item](inflect: true)")
        case .home, .packages, .backgroundItems, .extensions, .plugins, .tweaks, .terminal, .history: nil
        }
        return words.map { String($0.characters) }
    }

    /// The sentence for what `looked` holds, or nil while the tool hasn't looked or found nothing.
    func summary(of looked: Looked?) -> AttributedString? {
        guard let looked, looked.count > 0 else { return nil }
        return sentence(for: looked)
    }
}

extension AppLibrary {
    var summary: AttributedString? {
        guard hasLoaded else { return nil }
        let count = apps.count
        let known = sizes.values.cappedSum
        let total = SizeTotal(known: known, isComplete: sizes.count >= count)
        let size = known > 0 ? AttributedString(localized: "\(total.text) in ^[\(count) app](inflect: true).") : AttributedString(localized: "^[\(count) app](inflect: true).")
        guard let updates = Tool.applications.summary(of: Looked(count: appsWithUpdates.count, size: nil)) else { return size }
        return size + AttributedString("\n") + updates
    }
}

extension OrphanLibrary {
    var summary: AttributedString? { Tool.orphans.summary(of: looked) }
}

extension DeveloperLibrary {
    var summary: AttributedString? { Tool.developer.summary(of: looked) }
}

extension ProjectLibrary {
    var summary: AttributedString? { Tool.projects.summary(of: looked) }
}

extension SpaceLibrary {
    var summary: AttributedString? { Tool.space.summary(of: looked) }
}

extension InstallerLibrary {
    var summary: AttributedString? { Tool.installers.summary(of: looked) }
}

extension HomebrewLibrary {
    var summary: AttributedString? {
        guard let packages, !packages.isEmpty else { return nil }
        let count = AttributedString(localized: "^[\(packages.count) package](inflect: true).")
        guard let updates = Tool.homebrew.summary(of: looked) else { return count }
        return count + AttributedString("\n") + updates
    }
}

extension FileSearchLibrary {
    var summary: AttributedString? {
        results.flatMap { results in
            Tool.fileSearch.summary(of: Looked(count: results.files.count, size: SizeTotal(known: results.files.map(\.size).cappedSum, isComplete: true)))
        }
    }
}

extension DuplicateLibrary {
    var summary: AttributedString? { Tool.duplicates.summary(of: looked) }
}

extension CloudLibrary {
    var summary: AttributedString? { Tool.cloud.summary(of: looked) }
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
    var summary: AttributedString? { Tool.intel.summary(of: looked) }
}

extension RemovalHistoryStore {
    var summary: AttributedString? {
        guard !batches.isEmpty else { return nil }
        return AttributedString(localized: "^[\(batches.count) removal](inflect: true).")
    }
}

extension View {
    /// Tells VoiceOver how a scan ended, since the list fills in silently: what it found, that it was stopped, or
    /// `couldNotLook`, the title of the page's message, in place of "Nothing found." when it could not look. The
    /// summary is worked out only then, so the page does not depend on everything it reads.
    func announcesScan(
        _ isScanning: Bool,
        found summary: @autoclosure @escaping () -> AttributedString?,
        couldNotLook: LocalizedStringResource? = nil,
        wasStopped: Bool = false
    ) -> some View {
        onChange(of: isScanning) { wasScanning, scanning in
            guard wasScanning, !scanning else { return }
            let nothing = couldNotLook.map { AttributedString(localized: $0) }
                ?? AttributedString(localized: "Nothing found.")
            let words = wasStopped ? AttributedString(localized: "Scan stopped.") : summary() ?? nothing
            AccessibilityNotification.Announcement(words).post()
        }
    }
}
