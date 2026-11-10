import Foundation

/// A disk image made for a test and attached as Finder opens one through macOS's newer disk image service, whose
/// process belongs to another account, with nothing mounted. It is detached when the test lets go of it.
final class AttachedImage {
    let url: URL
    private var device: String?

    init(at url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DiskImageTool.hdiutil("create", "-size", "1m", "-fs", "APFS", "-volname", "Probe", url.path)
        let answer = try DiskImageTool.diskutil(
            "image", "attach", "--plist", "--readOnly", "--nobrowse", "--noMount", url.path
        )
        let plist = try PropertyListSerialization.propertyList(from: answer, format: nil) as? [String: Any]
        let entities = plist?["system-entities"] as? [[String: Any]] ?? []
        device = entities.compactMap { $0["dev-entry"] as? String }.first
    }

    deinit {
        detach()
    }

    func detach() {
        guard let device else { return }
        _ = try? DiskImageTool.hdiutil("detach", "-force", "/dev/" + device)
        self.device = nil
    }
}
