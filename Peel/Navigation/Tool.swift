import Foundation
import PeelCore

/// A tool in the sidebar. The order of the cases is the order within each group, in the sidebar and in the View
/// menu, where the first nine tools get ⌘1 to ⌘9. The `.home` group (Home, Tweaks, Terminal, History) comes first.
nonisolated enum Tool: String, CaseIterable, Identifiable {
    case home

    // Apps: what is installed, where it came from, and what it left behind.
    case applications
    case orphans
    case intel
    case packages
    case homebrew

    // Storage: finding and freeing room, from the whole disk down to one kind of file.
    case space
    case developer
    case projects
    case installers
    case duplicates
    case cloud
    case fileSearch

    // System: what runs and what extends macOS.
    case backgroundItems
    case extensions
    case plugins

    case tweaks
    case terminal
    case history

    enum Group: CaseIterable {
        case home
        case apps
        case storage
        case system
    }

    var id: Self { self }

    var group: Group {
        switch self {
        case .home, .tweaks, .terminal, .history: .home
        case .applications, .orphans, .intel, .packages, .homebrew: .apps
        case .space, .developer, .projects, .installers, .duplicates, .cloud, .fileSearch: .storage
        case .backgroundItems, .extensions, .plugins: .system
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .home: "Home"
        case .applications: "Applications"
        case .orphans: "Orphaned Files"
        case .intel: "Intel Software"
        case .packages: "Package Receipts"
        case .homebrew: "Homebrew"
        case .space: "Space"
        case .developer: "Developer"
        case .projects: "Build Artifacts"
        case .installers: "Installers and Backups"
        case .duplicates: "Duplicates"
        case .cloud: "iCloud Drive"
        case .fileSearch: "File Search"
        case .backgroundItems: "Background Items"
        case .extensions: "Extensions"
        case .plugins: "Plug-ins"
        case .tweaks: "Tweaks"
        case .terminal: "Terminal"
        case .history: "History"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .applications: "square.grid.2x2"
        case .orphans: "questionmark.folder"
        case .intel: "cpu"
        case .packages: "shippingbox"
        case .homebrew: "mug"
        case .space: "internaldrive"
        case .developer: "hammer"
        case .projects: "folder.badge.gearshape"
        case .installers: "arrow.down.app"
        case .duplicates: "doc.on.doc"
        case .cloud: "icloud"
        case .fileSearch: "doc.text.magnifyingglass"
        case .backgroundItems: "gearshape.2"
        case .extensions: "puzzlepiece.extension"
        case .plugins: "powerplug"
        case .tweaks: "slider.horizontal.3"
        case .terminal: "terminal"
        case .history: "clock.arrow.circlepath"
        }
    }
}

extension Tool {
    /// Whether the sidebar may leave this tool out. Home, Applications, and History always stay: Applications is
    /// where the Finder extension, `peel://open`, and the update notices lead, and History is the way back.
    var canBeHidden: Bool {
        switch self {
        case .home, .applications, .history: false
        default: true
        }
    }

    /// Whether the sidebar shows this tool to a person who never chose: what someone who uninstalls and frees space
    /// rarely needs starts off, and Homebrew shows while Homebrew is installed.
    func isShownByDefault(homebrewIsInstalled: Bool) -> Bool {
        switch self {
        case .backgroundItems, .extensions, .plugins, .projects, .intel, .terminal: false
        case .homebrew: homebrewIsInstalled
        default: true
        }
    }

    /// The tools the sidebar leaves out: those the person chose to, and those never chosen that start off.
    static func hidden(by choices: SidebarChoices, homebrewIsInstalled: Bool) -> Set<Tool> {
        Set(allCases.filter { tool in
            let byDefault = tool.isShownByDefault(homebrewIsInstalled: homebrewIsInstalled)
            return tool.canBeHidden && !choices.shows(tool.rawValue, byDefault: byDefault)
        })
    }
}

extension Tool.Group {
    var title: LocalizedStringResource? {
        switch self {
        case .home: nil
        case .apps: "Apps"
        case .storage: "Storage"
        case .system: "System"
        }
    }

    var tools: [Tool] {
        Tool.allCases.filter { $0.group == self }
    }
}
