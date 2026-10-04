import AppIntents
import Foundation
import PeelCore

/// A place in Peel that a Shortcut can open. Opening one only shows the page: nothing is removed, and every
/// decision is left to the user.
enum PeelPlace: String, AppEnum {
    case home
    case applications
    case orphanedFiles
    case developerCaches
    case buildArtifacts
    case installers
    case duplicates
    case iCloudDrive
    case space
    case history
    // A saved Shortcut stores the raw value, so a case is never renamed. New places are added at the end.
    case intelSoftware
    case packageReceipts
    case homebrew
    case fileSearch
    case backgroundItems
    case extensions
    case plugins
    case tweaks
    case terminal

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Place in Peel")

    static let caseDisplayRepresentations: [PeelPlace: DisplayRepresentation] = [
        .home: "Home",
        .applications: "Applications",
        .orphanedFiles: "Orphaned Files",
        .developerCaches: "Developer",
        .buildArtifacts: "Build Artifacts",
        .installers: "Installers and Backups",
        .duplicates: "Duplicates",
        .iCloudDrive: "iCloud Drive",
        .space: "Space",
        .history: "History",
        .intelSoftware: "Intel Software",
        .packageReceipts: "Package Receipts",
        .homebrew: "Homebrew",
        .fileSearch: "File Search",
        .backgroundItems: "Background Items",
        .extensions: "Extensions",
        .plugins: "Plug-ins",
        .tweaks: "Tweaks",
        .terminal: "Terminal",
    ]

    var tool: Tool {
        switch self {
        case .home: .home
        case .applications: .applications
        case .orphanedFiles: .orphans
        case .developerCaches: .developer
        case .buildArtifacts: .projects
        case .installers: .installers
        case .duplicates: .duplicates
        case .iCloudDrive: .cloud
        case .space: .space
        case .history: .history
        case .intelSoftware: .intel
        case .packageReceipts: .packages
        case .homebrew: .homebrew
        case .fileSearch: .fileSearch
        case .backgroundItems: .backgroundItems
        case .extensions: .extensions
        case .plugins: .plugins
        case .tweaks: .tweaks
        case .terminal: .terminal
        }
    }
}

struct ShowInPeel: AppIntent {
    static let title: LocalizedStringResource = "Show in Peel"
    static let description = IntentDescription(
        "Opens Peel at the place you choose. Nothing is removed: Peel shows you what is there and waits.",
        categoryName: "Navigation"
    )
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Place")
    var place: PeelPlace

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$place) in Peel")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        Navigator.shared.requestedTool = place.tool
        return .result()
    }
}

/// An installed app, as Shortcuts and Spotlight offer it: chosen from the apps on the Mac rather than typed by
/// hand. Its `id` is the bundle identifier, so a Shortcut keeps working after the app moves.
struct InstalledAppEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "App")
    static let defaultQuery = InstalledAppQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(_ app: InstalledApp) {
        id = app.bundleIdentifier
        name = app.name
    }
}

struct InstalledAppQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [InstalledAppEntity] {
        let wanted = Set(identifiers)
        return await AppCatalog.installedApps().filter { wanted.contains($0.bundleIdentifier) }
            .map(InstalledAppEntity.init)
    }

    func entities(matching string: String) async throws -> [InstalledAppEntity] {
        await AppCatalog.installedApps()
            .filter { app in
                app.names.contains { SearchText.matches($0, string) }
                    || SearchText.matches(app.bundleIdentifier, string)
            }
            .map(InstalledAppEntity.init)
    }

    func suggestedEntities() async throws -> [InstalledAppEntity] {
        await AppCatalog.installedApps().map(InstalledAppEntity.init)
    }
}

struct ShowLeftoversInPeel: AppIntent {
    static let title: LocalizedStringResource = "Show What an App Leaves Behind"
    static let description = IntentDescription(
        "Opens Peel on an app and lists the files it would leave behind. Nothing is removed until you say so.",
        categoryName: "Navigation"
    )
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "App")
    var app: InstalledAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Show what \(\.$app) leaves behind")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Checked again here, because the app may have been removed after it was chosen. The error lets the
        // Shortcut handle that case, instead of opening an empty page.
        guard let installed = await AppCatalog.installedApps().first(where: { $0.bundleIdentifier == app.id }) else {
            throw NoSuchApp(name: app.name)
        }
        Navigator.shared.requestedApp = installed.url
        Navigator.shared.requestedTool = .applications
        return .result()
    }
}

/// The error a Shortcut gets when the app it names is not installed. The app is matched by bundle identifier, so
/// another app with the same name does not count. `AppIntentError(description:)` needs macOS 27 and Peel runs on
/// macOS 26, so the message is this error's own `localizedStringResource`.
struct NoSuchApp: Error, CustomLocalizedStringResourceConvertible {
    let name: String

    var localizedStringResource: LocalizedStringResource {
        "\(name), chosen in this shortcut, isn’t installed on this Mac. Choose the app again."
    }
}

struct PeelShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowInPeel(),
            phrases: [
                "Show \(\.$place) in \(.applicationName)",
                "Open \(\.$place) in \(.applicationName)",
            ],
            shortTitle: "Show in Peel",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: ShowLeftoversInPeel(),
            phrases: [
                "Show what an app leaves behind with \(.applicationName)",
                "Find leftovers with \(.applicationName)",
            ],
            shortTitle: "Show Leftovers",
            systemImageName: "questionmark.folder"
        )
    }
}
