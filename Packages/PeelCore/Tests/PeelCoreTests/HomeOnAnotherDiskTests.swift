import Darwin
import Foundation
@testable import PeelCore
@testable import PeelPrivileged
import Testing

/// An account whose home folder is on another disk than macOS: what the helper moves from the startup disk goes to the
/// Trash macOS keeps for that account there, `.Trashes/<uid>` at the top of the disk, which `top` stands in for here.
struct HomeOnAnotherDiskTests {
    enum HomeDisk: String, CaseIterable {
        case apfsWithOwners, apfs, exFAT

        func mount(at url: URL) throws -> ScratchVolume {
            switch self {
            case .apfsWithOwners: try ScratchVolume(fileSystem: "APFS", mountedAt: url, owners: true)
            case .apfs: try ScratchVolume(fileSystem: "APFS", mountedAt: url)
            case .exFAT: try ScratchVolume(fileSystem: "ExFAT", mountedAt: url)
            }
        }
    }

    private func path(_ relative: String, in directory: borrowing TemporaryDirectory) -> String {
        directory.url.appending(path: relative).path(percentEncoded: false)
    }

    private func home(on disk: ScratchVolume) throws -> String {
        let home = disk.url.appending(path: "home").path(percentEncoded: false)
        for folder in [".Trash", "Library/Caches"] {
            try FileManager.default.createDirectory(atPath: home + "/" + folder, withIntermediateDirectories: true)
        }
        return home
    }

    private func policy(
        home: String,
        in directory: borrowing TemporaryDirectory,
        trustedOwner: uid_t = getuid()
    ) -> PrivilegedPathPolicy {
        let caches = path("root/Library/Caches", in: directory)
        return PrivilegedPathPolicy(
            homeDirectory: home, systemLocations: [caches], applicationLocations: [], restoreLocations: [caches],
            disk: path("top", in: directory), trustedOwner: trustedOwner
        )
    }

    private func top(_ directory: borrowing TemporaryDirectory) throws -> String {
        try #require(PrivilegedPathPolicy.resolvedPath(try directory.directory("top").path(percentEncoded: false)))
    }

    /// `.Trashes` is open to nobody but its owner, who can't list it either, so the folder is opened again before the
    /// test's folder is taken away.
    private func openingAgain(_ top: String) {
        chmod(top + "/.Trashes", 0o700)
    }

    private func moved(
        _ paths: [String],
        home: String,
        policy: PrivilegedPathPolicy,
        ledger: HelperLedger
    ) -> (moved: [String: String], failed: [String: String]) {
        HelperOperations.moveToTrash(
            account: getuid(), version: HelperIdentity.protocolVersion, approval: Data(), paths: paths,
            caller: { _ in .success(HelperRequest.Caller(user: getuid(), homeDirectory: home)) },
            policy: { _ in policy }, ledger: { ledger }
        )
    }

    @Test(arguments: HomeDisk.allCases)
    func whatTheHelperServesOnTheStartupDiskGoesToTheAccountsTrashThere(home kind: HomeDisk) throws {
        let directory = try TemporaryDirectory()
        let disk = try kind.mount(at: directory.url.appending(path: "Disk"))
        let home = try home(on: disk)
        let top = try top(directory)
        defer { openingAgain(top) }
        let item = try directory.file("root/Library/Caches/org.example.cache", contents: Data("cache".utf8))
            .path(percentEncoded: false)
        let policy = policy(home: home, in: directory)
        let ledger = try #require(HelperLedger(at: directory.url.appending(path: "private/moved.plist")))

        let result = moved([item], home: home, policy: policy, ledger: ledger)

        let trash = top + "/.Trashes/\(getuid())"
        #expect(result.failed.isEmpty, "the helper still moves nothing for a home on another disk")
        #expect(result.moved[item] == trash + "/org.example.cache")
        #expect(FileManager.default.fileExists(atPath: trash + "/org.example.cache"))
        var trashes = stat(), own = stat()
        #expect(lstat(top + "/.Trashes", &trashes) == 0 && trashes.st_mode & 0o7777 == 0o1311)
        #expect(trashes.st_uid == getuid(), "the folder of every account's Trash on the disk is root's")
        #expect(lstat(trash, &own) == 0 && own.st_mode & 0o7777 == 0o700 && own.st_uid == getuid())

        let back = HelperPutBack.run(trash + "/org.example.cache", to: item, for: getuid(), policy: policy, ledger: {
            ledger
        })
        #expect(back == nil)
        #expect(try String(contentsOfFile: item, encoding: .utf8) == "cache")
    }

    @Test func whatIsInTheLibraryOfAHomeOnAnotherDiskStaysUnrecorded() throws {
        let directory = try TemporaryDirectory()
        let disk = try HomeDisk.apfsWithOwners.mount(at: directory.url.appending(path: "Disk"))
        let home = try home(on: disk)
        let top = try top(directory)
        defer { openingAgain(top) }
        let item = home + "/Library/Caches/org.example.cache"
        try Data("cache".utf8).write(to: URL(filePath: item))
        let policy = policy(home: home, in: directory)
        let ledger = try #require(HelperLedger(at: directory.url.appending(path: "private/moved.plist")))
        let opened = try policy.open(item).get()

        let result = moved([item], home: home, policy: policy, ledger: ledger)

        #expect(result.moved.isEmpty)
        #expect(result.failed[item] == HelperRefusal.anotherDisk.rawValue)
        #expect(FileManager.default.fileExists(atPath: item))
        #expect(try ledger.origin(of: opened, movedBy: getuid()) == nil)
    }

    @Test func whatGoesBackToAHomeOnAnotherDiskStaysInTheTrash() throws {
        let directory = try TemporaryDirectory()
        let disk = try HomeDisk.apfsWithOwners.mount(at: directory.url.appending(path: "Disk"))
        let home = try home(on: disk)
        let top = try top(directory)
        defer { openingAgain(top) }
        let policy = policy(home: home, in: directory)
        let ledger = try #require(HelperLedger(at: directory.url.appending(path: "private/moved.plist")))
        let trash = try #require(policy.openTrash(ownedBy: getuid(), making: true))
        let trashed = trash.path + "/org.example.cache"
        try Data("the app's".utf8).write(to: URL(filePath: trashed))
        let library = try #require(PrivilegedPathPolicy.resolvedPath(home + "/Library/Caches"))
        let inTrash = try OpenItem.at(trashed).get()
        var info = stat()
        #expect(lstat(trashed, &info) == 0)
        let fromTheHome = OpenItem(
            path: library + "/org.example.cache", name: "org.example.cache", parent: inTrash.parent, status: info
        )
        #expect(ledger.record([fromTheHome], movedBy: getuid()))

        let refusal = HelperPutBack.run(
            trashed, to: library + "/org.example.cache", for: getuid(), policy: policy, ledger: { ledger }
        )

        #expect(refusal == HelperRefusal.anotherDisk.rawValue)
        #expect(try String(contentsOfFile: trashed, encoding: .utf8) == "the app's")
        #expect(!FileManager.default.fileExists(atPath: library + "/org.example.cache"))
    }

    @Test func peelOffersWhatTheHelperCanMoveForAHomeOnAnotherDisk() throws {
        let directory = try TemporaryDirectory()
        let disk = try HomeDisk.apfs.mount(at: directory.url.appending(path: "Disk"))
        let home = try home(on: disk)
        try directory.file("root/Applications/Example.app/Contents/Info.plist")
        let root = directory.url.appending(path: "root")
        let reach = HelperReach(environment: SearchEnvironment(homeDirectory: URL(filePath: home), rootDirectory: root))

        #expect(!reach.isBeyond(root.appending(path: "Applications/Example.app")), "Peel leaves it all in place")
        #expect(reach.isBeyond(URL(filePath: home + "/Library/Caches")), "the helper never takes it to another disk")
    }

    @Test func theStartupDisksTrashIsNamedWhereMacOSKeepsIt() throws {
        let directory = try TemporaryDirectory()
        let disk = try HomeDisk.apfs.mount(at: directory.url.appending(path: "Disk"))
        let away = URL(filePath: try home(on: disk)), here = try directory.directory("home")
        let startupDisk = try #require(AccountTrash.top(ofTheDiskOf: "/private/var/db"))

        #expect(startupDisk == "/System/Volumes/Data", "the startup disk's data is mounted there")
        let app = URL(filePath: "/Applications/Example.app")
        #expect(
            VolumeTrashes.trash(forItemAt: app, home: away).path(percentEncoded: false)
                == "/System/Volumes/Data/.Trashes/\(getuid())/"
        )
        #expect(
            VolumeTrashes.trash(forItemAt: app, home: here).path(percentEncoded: false)
                == here.path(percentEncoded: false) + ".Trash/"
        )
    }

    @Test func whatIsInTheStartupDisksTrashIsNeverMovedAgain() {
        for path in ["/System/Volumes/Data/.Trashes", "/System/Volumes/Data/.Trashes/501/Example.app"] {
            #expect(ProtectedData.refuses(path, home: "/Users/someone"), "\(path) would move again")
        }
    }

    @Test func whatAMoveCutShortLeftGoesToTheTrashOnTheStartupDiskForAHomeElsewhere() throws {
        let directory = try TemporaryDirectory()
        let disk = try HomeDisk.apfs.mount(at: directory.url.appending(path: "Disk"))
        let home = try home(on: disk)
        let top = try top(directory)
        defer { openingAgain(top) }
        let folder = try directory.directory("ledger").path(percentEncoded: false)
        chmod(folder, 0o700)
        let staging = folder + "/Staging"
        mkdir(staging, 0o700)
        try Data("left".utf8).write(to: URL(filePath: staging + "/\(getuid()).\(UUID().uuidString).Example.app"))

        HelperLedger.recoverStaged(in: folder, homeDirectory: { _ in home }, disk: top, trustedOwner: getuid())

        #expect(FileManager.default.fileExists(atPath: top + "/.Trashes/\(getuid())/Example.app"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: staging).isEmpty)
    }

    @Test func peelsLedgerGoesToTheTrashOnTheStartupDiskForAHomeElsewhere() throws {
        let directory = try TemporaryDirectory()
        let disk = try HomeDisk.apfs.mount(at: directory.url.appending(path: "Disk"))
        let home = try home(on: disk)
        let top = try top(directory)
        defer { openingAgain(top) }
        let policy = policy(home: home, in: directory)
        var into: String?

        let refusal = HelperOperations.moveLedgerToTrash(
            account: getuid(), version: HelperIdentity.protocolVersion,
            caller: { _ in .success(HelperRequest.Caller(user: getuid(), homeDirectory: home)) },
            policy: { _ in policy },
            moveFolder: { trash, _ in
                into = trash.path
                return .success(nil)
            }
        )

        #expect(refusal == nil)
        #expect(into == top + "/.Trashes/\(getuid())")
    }

    @Test func theDisksTrashIsOpenedOnlyWhenItIsRootsAndTheAccountsOwn() throws {
        let directory = try TemporaryDirectory()
        let disk = try HomeDisk.apfs.mount(at: directory.url.appending(path: "Disk"))
        let home = try home(on: disk)
        let top = try top(directory)
        defer { openingAgain(top) }
        let trashes = top + "/.Trashes", own = trashes + "/\(getuid())"
        let elsewhere = try directory.directory("elsewhere").path(percentEncoded: false)
        let fileManager = FileManager.default
        func opened(trustedOwner: uid_t = getuid(), user: uid_t = getuid()) -> String? {
            policy(home: home, in: directory, trustedOwner: trustedOwner).openTrash(ownedBy: user, making: true)?.path
        }
        func clear() throws {
            chmod(trashes, 0o700)
            let isThere = (try? fileManager.destinationOfSymbolicLink(atPath: trashes)) != nil
                || fileManager.fileExists(atPath: trashes)
            if isThere { try fileManager.removeItem(atPath: trashes) }
        }

        #expect(policy(home: home, in: directory).openTrash(ownedBy: getuid()) == nil, "Put Back made a Trash")
        #expect(!fileManager.fileExists(atPath: trashes))

        try fileManager.createSymbolicLink(atPath: trashes, withDestinationPath: elsewhere)
        #expect(opened() == nil, "ATTACK SUCCEEDED: the Trash was a link to a folder another account chose")
        #expect(try fileManager.contentsOfDirectory(atPath: elsewhere).isEmpty)

        try clear()
        try Data().write(to: URL(filePath: trashes))
        #expect(opened() == nil, "a file took the Trash's name")

        try clear()
        mkdir(trashes, 0o777)
        chmod(trashes, 0o777)
        #expect(opened() == nil, "ATTACK SUCCEEDED: any account could swap the folder of this account's Trash")
        chmod(trashes, 0o1777)
        #expect(opened() == own, "a folder anyone can add to, but no one can take another's folder from")

        try clear()
        #expect(opened(trustedOwner: 0) == nil, "ATTACK SUCCEEDED: the folder of the disk's Trashes is not root's")

        try clear()
        mkdir(trashes, 0o700)
        try fileManager.createSymbolicLink(atPath: own, withDestinationPath: elsewhere)
        #expect(opened() == nil, "ATTACK SUCCEEDED: the account's Trash was a link")

        try clear()
        mkdir(trashes, 0o700)
        mkdir(trashes + "/\(getuid() + 1)", 0o700)
        #expect(opened(user: getuid() + 1) == nil, "ATTACK SUCCEEDED: another account's folder took this one's place")
    }

    @Test func aTrashSwappedAfterItOpenedSendsNothingElsewhere() throws {
        let directory = try TemporaryDirectory()
        let disk = try HomeDisk.apfs.mount(at: directory.url.appending(path: "Disk"))
        let home = try home(on: disk)
        let top = try top(directory)
        defer { openingAgain(top) }
        let item = try directory.file("root/Library/Caches/org.example.cache", contents: Data("cache".utf8))
            .path(percentEncoded: false)
        let policy = policy(home: home, in: directory)
        let trash = try #require(policy.openTrash(ownedBy: getuid(), making: true))
        let decoy = try directory.directory("decoy").path(percentEncoded: false)
        chmod(top + "/.Trashes", 0o700)
        try FileManager.default.moveItem(atPath: top + "/.Trashes", toPath: top + "/.Trashes-aside")
        try FileManager.default.createSymbolicLink(atPath: top + "/.Trashes", withDestinationPath: decoy)

        _ = TrashMover.move(try policy.open(item).get(), into: trash)

        #expect(FileManager.default.fileExists(atPath: top + "/.Trashes-aside/\(getuid())/org.example.cache"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: decoy).isEmpty)
        try FileManager.default.removeItem(atPath: top + "/.Trashes")
        try FileManager.default.moveItem(atPath: top + "/.Trashes-aside", toPath: top + "/.Trashes")
    }
}
