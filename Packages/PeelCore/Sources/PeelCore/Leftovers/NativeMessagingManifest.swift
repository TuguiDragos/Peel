import Foundation

/// A browser's native messaging manifest, which names the program the browser starts for an extension.
enum NativeMessagingManifest {
    /// The program the manifest at `url` names, or nil when it can't be told: a manifest is a small JSON file, and a
    /// NUL in the path would end it where the kernel reads it.
    static func program(at url: URL) -> String? {
        guard url.pathExtension == "json", let data = BoundedRead.data(at: url, maximum: 64 * 1_024),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let program = manifest["path"] as? String, program.hasPrefix("/"), !program.utf8.contains(0)
        else { return nil }
        return program
    }
}
