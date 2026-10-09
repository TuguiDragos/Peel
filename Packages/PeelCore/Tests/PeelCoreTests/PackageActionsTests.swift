import Foundation
@testable import PeelCore
import Synchronization
import Testing

/// A receipt is two files in `private/var/db/receipts` on the volume the package went to, and macOS counts the
/// package as installed only while they are there. Forgetting a receipt moves both to the Trash, so History can
/// put them back. `pkgutil --forget` would delete them for good, and they are the only record of what the
/// package installed.
struct PackageActionsTests {
    private func receipt(_ identifier: String, on volume: URL) -> PackageReceipt {
        PackageReceipt(
            identifier: identifier, version: "1.0", installDate: nil, volume: volume,
            items: [], nothingLeftOnDisk: true
        )
    }

    @Test func aReceiptIsItsTwoFiles() throws {
        let directory = try TemporaryDirectory()
        try directory.file("private/var/db/receipts/com.example.tool.bom")
        try directory.file("private/var/db/receipts/com.example.tool.plist")
        try directory.file("private/var/db/receipts/com.example.tool.extra.plist")

        let files = PackageActions.receiptFiles(of: "com.example.tool", onVolume: directory.url)

        #expect(files.map(\.lastPathComponent).sorted() == ["com.example.tool.bom", "com.example.tool.plist"])
    }

    @Test func namesAReceiptAsTheDiskWritesIt() throws {
        let directory = try TemporaryDirectory()
        try directory.file("private/var/db/receipts/com.Example.Tool.bom")
        try directory.file("private/var/db/receipts/com.Example.Tool.plist")

        let files = PackageActions.receiptFiles(of: "com.example.tool", onVolume: directory.url)

        #expect(files.map(\.lastPathComponent).sorted() == ["com.Example.Tool.bom", "com.Example.Tool.plist"])
    }

    /// The identifier becomes part of a file name, so one that could name anything other than a plain file in
    /// the receipts folder names nothing.
    @Test func anIdentifierThatIsAPathNamesNoReceipt() throws {
        let directory = try TemporaryDirectory()
        try directory.file("private/var/db/victim.bom")
        try directory.file("private/var/db/receipts/.hidden.plist")

        for identifier in ["../victim", "a/b", ".hidden", "", ".", ".."] {
            #expect(PackageActions.receiptFiles(of: identifier, onVolume: directory.url).isEmpty, "\(identifier.debugDescription) named a file")
        }
    }

    @Test func forgettingMovesTheReceiptToTheTrashThroughTheHelper() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("private/var/db/receipts/com.example.tool.bom")
        try directory.file("private/var/db/receipts/com.example.tool.plist")
        let asked = Mutex<[String]>([])
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"),
                rootDirectory: directory.url
            ),
            moveThroughHelper: { urls in
                asked.withLock { $0 += urls.map(\.lastPathComponent) }
                return TrashResult(trashed: urls.map { TrashedItem(originalURL: $0, trashedURL: $0, date: .now) })
            },
            moveToTrash: { _ in throw CocoaError(.fileWriteNoPermission) }
        )

        let result = await PackageActions.forget(receipt("com.example.tool", on: directory.url), through: service)

        #expect(asked.withLock { $0 }.sorted() == ["com.example.tool.bom", "com.example.tool.plist"])
        #expect(result.trashed.count == 2, "History needs both, or the receipt cannot be put back whole")
        #expect(result.failures.isEmpty)
    }

    /// A receipt that is not there is a failure the user is told about, not a silent success, and it names the
    /// receipt rather than the disk it was looked for on.
    @Test func aReceiptThatIsNotThereIsAFailure() async throws {
        let directory = try TemporaryDirectory()
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"),
                rootDirectory: directory.url
            ),
            moveToTrash: { _ in throw CocoaError(.fileWriteNoPermission) }
        )

        let result = await PackageActions.forget(receipt("com.example.gone", on: directory.url), through: service)

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.url.lastPathComponent) == ["com.example.gone.plist"])
    }
}
