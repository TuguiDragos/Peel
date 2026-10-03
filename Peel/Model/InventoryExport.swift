import AppKit
import Foundation
import PeelCore
import SwiftUI
import UniformTypeIdentifiers

/// Writes out what is installed and where it came from, to a file the user picks.
enum InventoryExport {
    /// Whether the list can be written: once the apps are read, and while Homebrew is installed, once its list is
    /// too, since without it every cask app's source would read "Unknown".
    @MainActor
    static func canExport(library: AppLibrary, homebrew: HomebrewLibrary) -> Bool {
        library.hasLoaded && !(homebrew.isInstalled && homebrew.packages == nil)
    }

    /// Asks the user where to save the list, writes it there, and says in an alert when it could not.
    @MainActor
    static func save(_ format: Inventory.Format, apps: [InstalledApp], homebrew: HomebrewLibrary) async {
        guard let failure = await run(format: format, apps: apps, homebrew: homebrew) else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "The list couldn’t be saved.")
        alert.informativeText = failure
        alert.runModal()
    }

    /// Returns nil when the file was written or the user canceled, and the error message otherwise.
    @MainActor
    private static func run(format: Inventory.Format, apps: [InstalledApp], homebrew: HomebrewLibrary) async -> String? {
        let contents: String
        var brewfile: String?
        // Homebrew writes the Brewfile, asked only once it has answered, so its definitions are on this Mac.
        if format == .brewfile, homebrew.hasAnswered, let installation = homebrew.installation {
            do {
                brewfile = try await Homebrew.brewfile(from: installation)
            } catch {
                return error.output
            }
        }
        do {
            contents = try await written(format, apps: apps, casks: homebrew.packages ?? [], brewfile: brewfile)
        } catch is Inventory.HomebrewDidNotAnswer {
            return String(localized: "Homebrew didn’t answer, so Peel has nothing to write a Brewfile from. Open Homebrew in Peel to see why.")
        } catch {
            return error.localizedDescription
        }

        let panel = NSSavePanel()
        // Brewfile is the name Homebrew looks for; the others are named in the reader's language.
        panel.nameFieldStringValue = format == .brewfile ? "Brewfile" : String(localized: "Peel Inventory.\(format.fileExtension)", comment: "A suggested file name. Translate the words before the dot. %@ is the file extension, such as json.")
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = String(localized: "Where should Peel save the list?")
        if let type = contentType(for: format) {
            panel.allowedContentTypes = [type]
        }
        guard await panel.begin() == .OK, let url = panel.url else { return nil }
        do {
            // Atomic, so a write that fails halfway leaves the old file as it was.
            try Data(contents.utf8).write(to: url, options: .atomic)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// The list as `format` writes it, worked out off the main actor, since it reads every app's download records.
    @concurrent
    private static func written(
        _ format: Inventory.Format, apps: [InstalledApp], casks: [HomebrewPackage], brewfile: String?
    ) async throws -> String {
        try Inventory.build(apps: apps, casks: casks, origins: .onThisMac, brewfile: brewfile).written(as: format)
    }

    private static func contentType(for format: Inventory.Format) -> UTType? {
        switch format {
        case .json: .json
        case .csv: .commaSeparatedText
        case .text: .plainText
        case .brewfile: nil
        }
    }
}

/// The formats of Export List of Apps, as the toolbar and the File menu both offer them.
struct ExportListMenuContent: View {
    let library: AppLibrary
    let homebrew: HomebrewLibrary

    var body: some View {
        ForEach(Inventory.Format.offered(by: homebrew), id: \.self) { format in
            Button(String(localized: format.title)) {
                Task { await InventoryExport.save(format, apps: library.apps, homebrew: homebrew) }
            }
        }
    }
}

extension Inventory.Format {
    /// What Export List of Apps offers: a Brewfile only while Homebrew is installed and not too old to write one.
    @MainActor
    static func offered(by homebrew: HomebrewLibrary) -> [Inventory.Format] {
        allCases.filter { $0 != .brewfile || (homebrew.isInstalled && homebrew.installation?.writesABrewfile != false) }
    }

    var title: LocalizedStringResource {
        switch self {
        case .json: "JSON…"
        case .csv: "Spreadsheet…"
        case .text: "Plain Text…"
        case .brewfile: "Brewfile…"
        }
    }
}
