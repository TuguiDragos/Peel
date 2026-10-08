import Darwin
public import Foundation
internal import PeelPrivileged

public enum AccessState: Sendable, Hashable {
    case granted
    case missing
    case unknown
}

public enum FullDiskAccess {
    /// Checks whether Peel has Full Disk Access. macOS has no API for it, so Peel tries to list folders that only
    /// Full Disk Access opens, one after another, and the first clear answer decides.
    @concurrent
    public static func state(home: URL = .homeDirectory) async -> AccessState {
        let probes = [
            home.appending(path: ".Trash", directoryHint: .isDirectory),
            home.appending(path: "Library/Containers/com.apple.Safari", directoryHint: .isDirectory),
            home.appending(path: "Library/Safari", directoryHint: .isDirectory),
        ]
        for probe in probes {
            let state = canList(probe)
            if state != .unknown { return state }
        }
        return .unknown
    }

    /// Tries to list `url`. A privacy (TCC) refusal fails with `EPERM`, which means access is missing. Any other
    /// error is unknown: `EACCES`, for example, comes from ordinary permissions, such as a `.Trash` that `sudo`
    /// left owned by root.
    static func canList(_ url: URL) -> AccessState {
        guard let directory = opendir(url.path(percentEncoded: false)) else {
            return errno == EPERM ? .missing : .unknown
        }
        closedir(directory)
        return .granted
    }

    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}

/// The link at `/usr/local/bin/peel` to the command line tool inside Peel: the command that creates it, and
/// whether it leads to this copy of Peel.
public enum CommandLineTool {
    public static let path = "/usr/local/bin/peel"
    /// Where Homebrew links the tool when it installs Peel on a Mac with Apple silicon. On an Intel Mac it links
    /// it at `path` itself.
    public static let homebrewPath = "/opt/homebrew/bin/peel"
    /// Every place a `peel` command of this copy's can be: the link Peel offers to make, and Homebrew's.
    public static let paths = [path, homebrewPath]

    /// Whether a `peel` command leads to this copy's tool, from any of `paths`.
    public static func isOnThePath(embedded: URL, at paths: [String] = paths) -> Bool {
        paths.contains { standing(at: $0, embedded: embedded) == .installed }
    }

    public enum Standing: Sendable, Hashable {
        case installed
        case missing
        /// A link to the tool inside another copy of Peel, moved or gone, or to this copy's tool when it does not run.
        /// Replacing it takes nothing but the link.
        case otherPeel
        /// A file that is not a link, or a link to anything but a Peel's tool. It may not be Peel's, so Peel never
        /// offers a command that replaces it.
        case somethingElse
    }

    /// Where Peel is running from. It decides whether a link to the tool inside Peel keeps working.
    public enum Place: Sendable, Hashable {
        /// `/Applications` or `~/Applications`, where an app stays put.
        case applications
        /// The temporary copy macOS runs an app from while it is still marked as downloaded (App Translocation).
        /// Its path changes every time and it is gone when the app quits, so no link may point into it.
        case temporaryCopy
        /// Anywhere else, such as Downloads, a disk image, or a build folder. An app there may still be moved.
        case elsewhere
    }

    public static func place(of bundle: URL = Bundle.main.bundleURL, home: URL = .homeDirectory) -> Place {
        let path = PathPattern.comparablePath(of: bundle)
        guard !path.contains("/AppTranslocation/") else { return .temporaryCopy }
        let applications = ["/Applications", PathPattern.comparablePath(of: home) + "/Applications"]
        return applications.contains { PathComponents.isPath(path, inside: $0) } ? .applications : .elsewhere
    }

    /// The shell command that links the tool, built from where Peel really is rather than a fixed path, or nil once the
    /// link leads to this copy's tool and where something that may not be Peel's is in the link's place. `ln -f`
    /// deletes what is there, so only a link to another Peel's tool is replaced. A single quote in the path is closed,
    /// escaped, and reopened, so the shell reads the path as written.
    public static func installCommand(embedded: URL, standing: Standing) -> String? {
        let path = embedded.path(percentEncoded: false).replacingOccurrences(of: "'", with: "'\\''")
        let link = switch standing {
        case .missing: "ln -s"
        case .otherPeel: "ln -sf"
        case .installed, .somethingElse: nil as String?
        }
        return link.map { "sudo mkdir -p /usr/local/bin && sudo \($0) '\(path)' \(CommandLineTool.path)" }
    }

    public static func standing(at path: String = CommandLineTool.path, embedded: URL) -> Standing {
        let manager = FileManager.default
        guard let destination = try? manager.destinationOfSymbolicLink(atPath: path) else {
            var info = stat()
            guard lstat(path, &info) == 0 else { return .missing }
            // A file that is not a link: something else named `peel`, not Peel's tool.
            return .somethingElse
        }
        let target = URL(filePath: destination, relativeTo: URL(filePath: path).deletingLastPathComponent())
            .standardizedFileURL
        guard target.path(percentEncoded: false) == embedded.standardizedFileURL.path(percentEncoded: false) else {
            return isAPeelsTool(target) ? .otherPeel : .somethingElse
        }
        return manager.isExecutableFile(atPath: target.path(percentEncoded: false)) ? .installed : .otherPeel
    }

    /// Whether `url` is where a copy of Peel keeps its tool: `<name>.app/Contents/Helpers/peel`.
    private static func isAPeelsTool(_ url: URL) -> Bool {
        let names = url.pathComponents
        return names.count >= 4 && names.suffix(3) == ["Contents", "Helpers", "peel"] && names[names.count - 4].hasSuffix(".app")
    }
}

/// App Management has no API, so only a removal shows whether Peel has it.
public enum AppManagement {
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!

    /// What a removal shows about App Management, or nil when it shows nothing. An app bundle Peel moved means
    /// granted. A bundle macOS refused to move from a folder the user can write to, when nothing locks it, means
    /// missing. Bundles the root helper moved don't count, since the helper doesn't need Peel's permission.
    public static func state(
        after result: TrashResult,
        appBundles: Set<URL>,
        movedByTheHelper: Set<URL> = []
    ) -> AccessState? {
        let asked = appBundles.subtracting(movedByTheHelper)
        if result.trashed.contains(where: { asked.contains($0.originalURL) }) {
            return .granted
        }
        for failure in result.failures where asked.contains(failure.url) && failure.reason == .notPermitted {
            if isRefusedForWantOfPermission(failure.url) { return .missing }
        }
        return nil
    }

    /// Whether a refused move of `url` points to App Management: the user can write to the bundle's folder, and
    /// nothing locks the bundle. The removal alert uses the same test.
    public static func isRefusedForWantOfPermission(_ url: URL) -> Bool {
        let canBeMoved = !FileAccess.requiresPrivilegesToRemove(url) || FileAccess.isProtectedByPrivacy(url)
        return canBeMoved && !FileAccess.isLocked(url)
    }
}
