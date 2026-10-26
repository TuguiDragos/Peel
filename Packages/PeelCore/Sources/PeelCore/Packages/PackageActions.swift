public import Foundation

public enum PackageActions {
    static let misplacedReceipt = "The receipt isn’t where macOS keeps receipts."
    static let forgottenReceipt = "It was already forgotten."

    /// Returns the receipt's files that exist: `<identifier>.bom` and `<identifier>.plist` in
    /// `private/var/db/receipts` on `volume`. macOS counts the package as installed only while they are there.
    /// The identifier becomes part of a file name, so one that could name anything but a plain file in that
    /// folder (empty, starting with `.`, or holding a `/`) gets no files.
    static func receiptFiles(of identifier: String, onVolume volume: URL) -> [URL] {
        guard !identifier.isEmpty, !identifier.hasPrefix("."), !identifier.contains("/") else { return [] }
        return ["bom", "plist"].map { receiptsFolder(onVolume: volume).appending(path: identifier + "." + $0) }
            .filter(\.isThere).map(PathPattern.spelledOnDisk)
    }

    /// When a receipt on `volume` last changed: the newest date of the folder macOS keeps them in and of what is in it.
    /// Writing, forgetting, or putting back a receipt changes the folder's; an upgrade rewrites a receipt in place,
    /// which changes only the file's. Nil when the folder can't be read.
    public static func receiptsChanged(
        onVolume volume: URL = URL(filePath: "/", directoryHint: .isDirectory)
    ) -> Date? {
        let folder = receiptsFolder(onVolume: volume)
        let path = folder.path(percentEncoded: false)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return nil }
        return ([folder] + names.map { folder.appending(path: $0) }).compactMap(modified).max()
    }

    private static func modified(_ url: URL) -> Date? {
        var info = stat()
        guard lstat(url.path(percentEncoded: false), &info) == 0 else { return nil }
        let time = info.st_mtimespec
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }

    private static func receiptsFolder(onVolume volume: URL) -> URL {
        volume.appending(path: "private/var/db/receipts", directoryHint: .isDirectory)
    }

    /// Moves the receipt to the Trash, so macOS stops counting the package as installed and History can put
    /// it back. `pkgutil --forget` would delete the same two files for good, and they are the only record of
    /// what the package installed. Files the package installed stay where they are.
    @concurrent
    public static func forget(_ receipt: PackageReceipt, exclusions: Exclusions = .none) async -> TrashResult {
        await forget(receipt, through: TrashService(exclusions: exclusions))
    }

    static func forget(_ receipt: PackageReceipt, through service: TrashService) async -> TrashResult {
        let files = receiptFiles(of: receipt.identifier, onVolume: receipt.volume)
        guard !files.isEmpty else {
            // Named by the file macOS would keep, so the failure says which receipt rather than which disk. With the
            // folder there, the receipt was forgotten some other way since Peel read it.
            let folder = receiptsFolder(onVolume: receipt.volume)
            let missing = folder.appending(path: receipt.identifier + ".plist")
            let why = folder.isRealFolder ? Self.forgottenReceipt : Self.misplacedReceipt
            return TrashResult(failures: [TrashFailure(url: missing, reason: .failed(why))])
        }
        return await service.trash(files, usingHelperFor: Set(files))
    }
}
