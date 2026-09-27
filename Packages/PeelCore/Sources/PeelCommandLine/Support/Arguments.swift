import ArgumentParser
import Foundation
import PeelCore

struct RemovalOptions: ParsableArguments {
    @Flag(help: "Move what Peel suggests to the Trash.")
    var remove = false

    @Flag(name: .customLong("dry-run"), help: "Show what would go without moving anything.")
    var dryRun = false

    @Flag(name: .shortAndLong, help: "Don't ask for confirmation.")
    var yes = false

    func validate(with output: OutputOptions) throws {
        guard remove || (!dryRun && !yes) else {
            throw ValidationError("--dry-run and --yes only go with --remove.")
        }
        if remove, output.json {
            try Cleanup.refuseJSON()
        }
        if remove, !yes, !dryRun {
            try Output.requireConfirmable()
        }
    }
}

struct OutputOptions: ParsableArguments {
    @Flag(help: "Print JSON instead of text.")
    var json = false
}

enum KindArgument: String, CaseIterable, ExpressibleByArgument {
    case documents
    case images
    case movies
    case audio
    case archives
    case diskImages = "disk-images"

    /// What `--help` and the manual page say beside each value.
    var defaultValueDescription: String {
        switch self {
        case .documents: "Text files, PDFs, and other documents, not source code"
        case .images: "Pictures and photos"
        case .movies: "Videos"
        case .audio: "Music and other sound"
        case .archives: "Zip files and other archives"
        case .diskImages: "Disk images, such as .dmg files"
        }
    }

    var fileKind: FileKind {
        switch self {
        case .documents: .documents
        case .images: .images
        case .movies: .movies
        case .audio: .audio
        case .archives: .archives
        case .diskImages: .diskImages
        }
    }
}

enum FormatArgument: String, CaseIterable, ExpressibleByArgument {
    case text
    case json
    case csv
    case brewfile

    /// What `--help` and the manual page say beside each value.
    var defaultValueDescription: String {
        switch self {
        case .text: "A line per app, with its version and where it came from"
        case .json: "Every detail, for scripts"
        case .csv: "A table for a spreadsheet"
        case .brewfile: "What Homebrew can install again, for brew bundle"
        }
    }

    var format: Inventory.Format {
        switch self {
        case .text: .text
        case .json: .json
        case .csv: .csv
        case .brewfile: .brewfile
        }
    }
}

/// A size in bytes, written as a number with an optional decimal unit such as 500KB or 1.5GB.
struct ByteSize: ExpressibleByArgument, Equatable {
    private static let units: [(suffix: String, multiplier: Double)] = [
        ("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("KB", 1e3), ("T", 1e12), ("G", 1e9), ("M", 1e6), ("K", 1e3), ("B", 1),
    ]

    let bytes: Int64

    init(bytes: Int64) {
        self.bytes = bytes
    }

    init?(argument: String) {
        let text = argument.trimmingCharacters(in: .whitespaces).uppercased()
        let unit = Self.units.first { text.hasSuffix($0.suffix) }
        let number = unit.map { String(text.dropLast($0.suffix.count)) } ?? text
        guard let value = Double(number.trimmingCharacters(in: .whitespaces)), value.isFinite, value >= 0 else { return nil }
        let bytes = (value * (unit?.multiplier ?? 1)).rounded()
        guard bytes < Double(Int64.max) else { return nil }
        self.bytes = Int64(bytes)
    }
}

/// Returns whether `url` is an existing folder, so a wrong path gets an error rather than an empty result.
func isAFolder(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue
}

extension URL {
    /// A folder or app given on the command line, relative to the current directory.
    init(argument: String) {
        let currentDirectory = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
        self = URL(filePath: (argument as NSString).expandingTildeInPath, directoryHint: .isDirectory, relativeTo: currentDirectory).standardizedFileURL
    }
}
