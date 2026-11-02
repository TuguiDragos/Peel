public import Foundation

public enum PackageActions {
    static let misplacedReceipt = "The receipt isn’t where macOS keeps receipts."
    static let forgottenReceipt = "It was already forgotten."

    /// Returns the receipt's files that exist: `<identifier>.bom` and `<identifier>.plist` in the folder macOS keeps
    /// the receipts of `volume` in. macOS counts the package as installed only while they are there. The identifier
    /// becomes part of a file name, so one that could name anything but a plain file in that folder (empty, starting
    /// with `.`, or holding a `/`) gets no files.
    static func receiptFiles(of identifier: String, onVolume volume: URL, home: URL = .homeDirectory) -> [URL] {
        guard !identifier.isEmpty, !identifier.hasPrefix("."), !identifier.contains("/") else { return [] }
        let folder = receiptsFolder(onVolume: volume, home: home)
        return ["bom", "plist"].map { folder.appending(path: identifier + "." + $0) }
            .filter(\.isThere).map(PathPattern.spelledOnDisk)
    }

    /// When a receipt last changed, on the startup disk or in the home folder.
    public static func receiptsChanged(
        root: URL = URL(filePath: "/", directoryHint: .isDirectory), home: URL = .homeDirectory
    ) -> Date? {
        [receiptsChanged(onVolume: root, home: home), receiptsChanged(onVolume: home, home: home)]
            .compactMap(\.self).max()
    }

    /// When a receipt on `volume` last changed: the newest date of the folder macOS keeps them in and of what is in it.
    /// Writing, forgetting, or putting back a receipt changes the folder's; an upgrade rewrites a receipt in place,
    /// which changes only the file's. Nil when the folder can't be read.
    static func receiptsChanged(onVolume volume: URL, home: URL = .homeDirectory) -> Date? {
        let folder = receiptsFolder(onVolume: volume, home: home)
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

    /// The folder macOS keeps the receipts of `volume` in. For a package installed for one account, `pkgutil` names
    /// that account's home folder as the volume, and the receipt is in the Library there.
    private static func receiptsFolder(onVolume volume: URL, home: URL) -> URL {
        let folder = isTheHome(volume, home: home) ? "Library/Receipts" : "private/var/db/receipts"
        return volume.appending(path: folder, directoryHint: .isDirectory)
    }

    /// Whether forgetting `receipt` takes Peel's helper: a disk's receipts are root's, and one in a home folder is that
    /// account's.
    public static func forgettingNeedsTheHelper(_ receipt: PackageReceipt, home: URL = .homeDirectory) -> Bool {
        !receipt.isInstalledForTheAccount(home: home)
    }

    static func isTheHome(_ volume: URL, home: URL) -> Bool {
        PathPattern.comparablePath(of: volume) == PathPattern.comparablePath(of: home)
    }

    /// Moves the receipt to the Trash, so macOS stops counting the package as installed and History can put
    /// it back. `pkgutil --forget` would delete the same two files for good, and they are the only record of
    /// what the package installed. Files the package installed stay where they are.
    @concurrent
    public static func forget(_ receipt: PackageReceipt, exclusions: Exclusions = .none) async -> TrashResult {
        await forget([receipt], through: TrashService(exclusions: exclusions))
    }

    /// Forgets several receipts in one removal, which History records as one.
    @concurrent
    public static func forget(_ receipts: [PackageReceipt], exclusions: Exclusions = .none) async -> TrashResult {
        await forget(receipts, through: TrashService(exclusions: exclusions))
    }

    static func forget(_ receipts: [PackageReceipt], through service: TrashService) async -> TrashResult {
        let home = service.environment.homeDirectory
        var files: [URL] = []
        var forTheHelper: [URL] = []
        var refused: [TrashFailure] = []
        for receipt in receipts {
            let own = receiptFiles(of: receipt.identifier, onVolume: receipt.volume, home: home)
            // Asked now, with the exclusions this removal goes by: one can come after the scan the receipt is from.
            if receipt.apps.contains(where: service.excludes) {
                refused += own.map { TrashFailure(url: $0, reason: .guarded(.excluded)) }
            } else if own.isEmpty {
                // Named by the file macOS would keep, so the failure says which receipt rather than which disk. With
                // the folder there, the receipt was forgotten some other way since Peel read it.
                let folder = receiptsFolder(onVolume: receipt.volume, home: home)
                let missing = folder.appending(path: receipt.identifier + ".plist")
                let why = folder.isRealFolder ? Self.forgottenReceipt : Self.misplacedReceipt
                refused.append(TrashFailure(url: missing, reason: .failed(why)))
            } else {
                files += own
                if forgettingNeedsTheHelper(receipt, home: home) { forTheHelper += own }
            }
        }
        guard !files.isEmpty else { return TrashResult(failures: refused) }
        var result = await service.trash(files, usingHelperFor: Set(forTheHelper))
        result.failures += refused
        return result
    }
}
