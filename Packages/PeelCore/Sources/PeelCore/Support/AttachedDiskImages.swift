import Foundation
internal import PeelPrivileged

/// The disk images attached right now, which `hdiutil info` names (`man hdiutil`). macOS's newer disk image service
/// holds one open under an account of its own, so the open files Peel reads can't show that it is in use.
enum AttachedDiskImages {
    /// The path of each, or nil when `hdiutil` didn't answer.
    @concurrent
    static func paths() async -> [String]? {
        guard case .success(let output) = await Subprocess.run("/usr/bin/hdiutil", ["info", "-plist"], timeout: 10),
              output.status == 0,
              let plist = try? PropertyListSerialization.propertyList(from: output.standardOutput, format: nil),
              let images = (plist as? [String: Any])?["images"] as? [[String: Any]]
        else { return nil }
        return images.compactMap { $0["image-path"] as? String }
    }

    /// Whether `url` is a kind of file `hdiutil attach` opens (`man hdiutil`): a UDIF image, a CD/DVD master, a
    /// hybrid image, a sparse image or bundle, or an older `.img`.
    static func mayBeAttached(_ url: URL) -> Bool {
        ["dmg", "cdr", "iso", "sparseimage", "sparsebundle", "img"].contains(url.pathExtension.lowercased())
    }
}
