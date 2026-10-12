import Darwin
public import Foundation

/// A folder browsers read native messaging manifests from, with the apps that read it besides its own browser.
public struct NativeMessagingFolder: Sendable, ExpressibleByStringLiteral {
    public let path: String
    public var alsoReadBy: [String] = []

    public init(stringLiteral path: String) {
        self.path = path
    }

    public init(_ path: String, alsoReadBy: [String]) {
        self.path = path
        self.alsoReadBy = alsoReadBy
    }

    /// Each browser's own documentation: Chrome's and Chromium's "Native messaging", MDN's "Native manifests" for
    /// Firefox, and Microsoft's "Native messaging" for Edge and its Beta, Dev, and Canary channels. Chrome's other
    /// channels keep theirs in their own user data folder (Chromium's `docs/user_data_dir.md`), and Chrome for
    /// Testing has its own in `/Library` (`chrome/common/chrome_paths.cc`). Every build of Brave reads Chrome's two
    /// on the Mac, where other apps leave their manifests (brave-core `app/brave_main_delegate.cc` at
    /// 5e268a047e51ba615c536db3aabbb782eb34550c, and its `app/theme/*/BRANDING` for each build's identifier).
    public static let inTheUsersLibrary: [NativeMessagingFolder] = [
        NativeMessagingFolder("Application Support/Google/Chrome/NativeMessagingHosts", alsoReadBy: ["com.brave.Browser"]),
        "Application Support/Google/Chrome Beta/NativeMessagingHosts",
        "Application Support/Google/Chrome Dev/NativeMessagingHosts",
        "Application Support/Google/Chrome Canary/NativeMessagingHosts",
        "Application Support/Google/Chrome for Testing/NativeMessagingHosts",
        "Application Support/Chromium/NativeMessagingHosts",
        "Application Support/Mozilla/NativeMessagingHosts",
        "Application Support/Microsoft Edge/NativeMessagingHosts",
        "Application Support/Microsoft Edge Beta/NativeMessagingHosts",
        "Application Support/Microsoft Edge Dev/NativeMessagingHosts",
        "Application Support/Microsoft Edge Canary/NativeMessagingHosts",
    ]

    public static let inTheMacsLibrary: [NativeMessagingFolder] = [
        NativeMessagingFolder("Google/Chrome/NativeMessagingHosts", alsoReadBy: ["com.brave.Browser"]),
        "Google/ChromeForTesting/NativeMessagingHosts",
        "Application Support/Chromium/NativeMessagingHosts",
        "Application Support/Mozilla/NativeMessagingHosts",
        "Microsoft/Edge/NativeMessagingHosts",
    ]
}

/// A browser's native messaging manifest, a small JSON file naming the program the browser starts for an extension.
public enum NativeMessagingManifest {
    public static let maximumSize = 64 * 1_024

    public static func isManifest(named name: String) -> Bool {
        URL(filePath: name).pathExtension == "json"
    }

    /// The program `data` names, or nil when it can't be told: a NUL in the path would end it where the kernel reads
    /// it.
    public static func program(in data: Data) -> String? {
        guard let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let program = manifest["path"] as? String, program.hasPrefix("/"), !program.utf8.contains(0)
        else { return nil }
        return program
    }

    /// Whether `program` is not there, on a disk that is connected: one on a disk that is away may come back.
    public static func isGone(_ program: String) -> Bool {
        var info = stat()
        guard stat(program, &info) != 0 else { return false }
        let error = errno
        guard error == ENOENT || error == ENOTDIR else { return false }
        let names = PathComponents.of(program)
        guard names.count > 2, names[0] == "Volumes" else { return true }
        var volume = stat()
        return lstat("/Volumes/" + names[1], &volume) == 0
    }
}
