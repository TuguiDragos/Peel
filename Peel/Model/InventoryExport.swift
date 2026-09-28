import AppKit
import Foundation
import PeelCore
import UniformTypeIdentifiers

/// Writes out what is installed and where it came from, to a file the user picks.
enum InventoryExport {
    /// Asks the user where to save the inventory, then writes it there. Returns nil when the file was written
    /// or the user canceled, and the error message otherwise.
    @MainActor
    static func run(format: Inventory.Format, apps: [InstalledApp], homebrew: HomebrewLibrary) async -> String? {
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
            contents = try Inventory.build(
                apps: apps, casks: homebrew.packages ?? [], origins: .onThisMac, brewfile: brewfile
            ).written(as: format)
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

    private static func contentType(for format: Inventory.Format) -> UTType? {
        switch format {
        case .json: .json
        case .csv: .commaSeparatedText
        case .text: .plainText
        case .brewfile: nil
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
