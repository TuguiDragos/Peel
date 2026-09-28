import Foundation

public enum PackageActions {
    static let misplacedReceipt = "The receipt isn’t where macOS keeps receipts."

    /// Returns the receipt's files that exist: `<identifier>.bom` and `<identifier>.plist` in
    /// `private/var/db/receipts` on `volume`. macOS counts the package as installed only while they are there.
    /// The identifier becomes part of a file name, so one that could name anything but a plain file in that
    /// folder (empty, starting with `.`, or holding a `/`) gets no files.
    static func receiptFiles(of identifier: String, onVolume volume: URL) -> [URL] {
        guard !identifier.isEmpty, !identifier.hasPrefix("."), !identifier.contains("/") else { return [] }
        return ["bom", "plist"].map { receiptsFolder(onVolume: volume).appending(path: identifier + "." + $0) }
            .filter(\.isThere)
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
            // Named by the file macOS would keep, so the failure says which receipt rather than which disk.
            let missing = receiptsFolder(onVolume: receipt.volume).appending(path: receipt.identifier + ".plist")
            return TrashResult(failures: [TrashFailure(url: missing, reason: .failed(Self.misplacedReceipt))])
        }
        return await service.trash(files, usingHelperFor: Set(files))
    }
}
