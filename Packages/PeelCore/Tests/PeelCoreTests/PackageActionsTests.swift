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

    @Test func knowsWhenAReceiptChanged() throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("private/var/db/receipts")
        let receipt = try directory.file("private/var/db/receipts/org.example.pkg.plist", bytes: 16)
        let written = Date(timeIntervalSince1970: 1_790_000_000)
        func date(_ date: Date, of item: URL) throws {
            let path = item.path(percentEncoded: false)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
        }
        try date(written, of: folder)
        try date(written, of: receipt)

        #expect(PackageActions.receiptsChanged(onVolume: directory.url) == written)
        // An upgrade rewrites a receipt in place, which leaves the folder's own date as it was.
        let upgraded = written + 3_600
        try date(upgraded, of: receipt)
        #expect(PackageActions.receiptsChanged(onVolume: directory.url) == upgraded)
        #expect(PackageActions.receiptsChanged(onVolume: directory.url.appending(path: "elsewhere")) == nil)
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

        let result = await PackageActions.forget([receipt("com.example.tool", on: directory.url)], through: service)

        #expect(asked.withLock { $0 }.sorted() == ["com.example.tool.bom", "com.example.tool.plist"])
        #expect(result.trashed.count == 2, "History needs both, or the receipt cannot be put back whole")
        #expect(result.failures.isEmpty)
    }

    @Test func forgetsSeveralReceiptsInOneRemoval() async throws {
        let directory = try TemporaryDirectory()
        for name in ["com.example.one", "com.example.two"] {
            try directory.file("private/var/db/receipts/\(name).bom")
            try directory.file("private/var/db/receipts/\(name).plist")
        }
        let requests = Mutex<[[String]]>([])
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"),
                rootDirectory: directory.url
            ),
            moveThroughHelper: { urls in
                requests.withLock { $0.append(urls.map(\.lastPathComponent).sorted()) }
                return TrashResult(trashed: urls.map { TrashedItem(originalURL: $0, trashedURL: $0, date: .now) })
            },
            moveToTrash: { _ in throw CocoaError(.fileWriteNoPermission) }
        )
        let receipts = ["com.example.one", "com.example.gone", "com.example.two"].map { receipt($0, on: directory.url) }

        let result = await PackageActions.forget(receipts, through: service)

        #expect(requests.withLock { $0 } == [[
            "com.example.one.bom", "com.example.one.plist", "com.example.two.bom", "com.example.two.plist",
        ]])
        #expect(result.trashed.count == 4)
        #expect(result.failures.map(\.url.lastPathComponent) == ["com.example.gone.plist"])
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

        let result = await PackageActions.forget([receipt("com.example.gone", on: directory.url)], through: service)

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.url.lastPathComponent) == ["com.example.gone.plist"])
        #expect(result.failures.map(\.reason) == [.failed(PackageActions.misplacedReceipt)])

        try directory.directory("private/var/db/receipts")
        let forgotten = await PackageActions.forget([receipt("com.example.gone", on: directory.url)], through: service)
        #expect(forgotten.failures.map(\.reason) == [.failed(PackageActions.forgottenReceipt)], "it was forgotten already")
    }
}
