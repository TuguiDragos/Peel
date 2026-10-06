import Foundation
@testable import PeelCore
import Testing

struct GreetingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Bucharest")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: hour, minute: minute))!
    }

    @Test func changesAtFiveTwelveAndEighteen() {
        #expect(Greeting.at(date(4, 59), calendar: calendar) == .evening)
        #expect(Greeting.at(date(5), calendar: calendar) == .morning)
        #expect(Greeting.at(date(11, 59), calendar: calendar) == .morning)
        #expect(Greeting.at(date(12), calendar: calendar) == .afternoon)
        #expect(Greeting.at(date(17, 59), calendar: calendar) == .afternoon)
        #expect(Greeting.at(date(18), calendar: calendar) == .evening)
        #expect(Greeting.at(date(23, 59), calendar: calendar) == .evening)
        #expect(Greeting.at(date(0), calendar: calendar) == .evening)
    }

    @Test func findsTheNextChange() {
        #expect(Greeting.change(after: date(3), calendar: calendar) == date(5))
        #expect(Greeting.change(after: date(5), calendar: calendar) == date(12))
        #expect(Greeting.change(after: date(12, 30), calendar: calendar) == date(18))
        #expect(
            Greeting.change(after: date(19), calendar: calendar) == calendar.date(
                byAdding: .day,
                value: 1,
                to: date(5)
            )!
        )
    }
}

struct DeviceInfoTests {
    @Test func storageStaysWithinTheVolume() {
        let storage = DeviceInfo.Storage(total: 245_107_195_904, free: 145_775_255_552)
        #expect(storage.used == 99_331_940_352)
        #expect(abs(storage.usedFraction - 0.405) < 0.001)

        #expect(DeviceInfo.Storage(total: 100, free: 200).free == 100)
        #expect(DeviceInfo.Storage(total: 100, free: -5).free == 0)
        #expect(DeviceInfo.Storage(total: 0, free: 0).usedFraction == 0)
    }

    /// What is free is the room macOS would make for an important file, which counts what it can purge. A volume
    /// that does not report that answers zero, and its plain free space is then what is free.
    @Test func freeSpaceIsThePlainFreeSpaceWhereTheVolumeDoesNotSayMore() {
        #expect(
            DeviceInfo.storage(total: 245_107_195_904, available: 48_015_052_800, important: 58_789_408_280).free
                == 58_789_408_280
        )
        #expect(DeviceInfo.storage(total: 536_829_952, available: 459_358_208, important: 0).free == 459_358_208)
        #expect(DeviceInfo.storage(total: nil, available: nil, important: nil) == DeviceInfo.Storage(total: 0, free: 0))
    }

    @MainActor @Test func readsTheFreeSpaceAwayFromTheMainActor() async {
        final class Turn {
            var taken = false
        }
        let device = await DeviceInfo.withoutTheModelName()
        let turn = Turn()
        Task { @MainActor in turn.taken = true }

        _ = await device.withStorageRead()

        #expect(turn.taken)
    }

    @Test func leavesOutAZeroPatchVersion() {
        #expect(
            DeviceInfo.versionString(OperatingSystemVersion(majorVersion: 26, minorVersion: 7, patchVersion: 0))
                == "26.7"
        )
        #expect(
            DeviceInfo.versionString(OperatingSystemVersion(majorVersion: 26, minorVersion: 7, patchVersion: 1))
                == "26.7.1"
        )
    }

    @Test func readsTheModelNameFromSystemProfiler() {
        let json = Data(#"{"SPHardwareDataType":[{"machine_name":"MacBook Air","machine_model":"Mac15,12"}]}"#.utf8)
        #expect(DeviceInfo.marketingName(fromSystemProfiler: json) == "MacBook Air")
        #expect(DeviceInfo.marketingName(fromSystemProfiler: Data(#"{"SPHardwareDataType":[]}"#.utf8)) == nil)
        #expect(DeviceInfo.marketingName(fromSystemProfiler: Data("not json".utf8)) == nil)
    }

    @Test func readsThisMac() async {
        let info = await DeviceInfo.current()
        #expect(!info.modelIdentifier.isEmpty)
        #expect(info.memory > 0)
        #expect(info.storage.total > 0)
        #expect(info.systemVersion.hasPrefix("\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)"))
    }
}

struct AccessTests {
    /// A privacy (TCC) refusal reads as `EPERM`. Plain permissions read as `EACCES`, which says nothing about
    /// Full Disk Access: a `.Trash` that `sudo` left owned by root is one example.
    @Test(.permissionsHold) func tellsApartReadableFoldersFromRefusedOnes() throws {
        let directory = try TemporaryDirectory()
        let readable = try directory.directory("readable")
        let refused = try directory.directory("refused")
        try directory.setPermissions(0, of: "refused")
        defer { try? directory.setPermissions(0o755, of: "refused") }

        #expect(FullDiskAccess.canList(readable) == .granted)
        #expect(FullDiskAccess.canList(refused) == .unknown, "ordinary permissions were read as a TCC refusal")
        #expect(FullDiskAccess.canList(directory.url.appending(path: "missing")) == .unknown)
    }

    /// The probes are tried in turn, and an unknown answer moves on to the next: a `.Trash` nobody can list must
    /// not keep the Safari folders from being asked.
    @Test(.permissionsHold) func keepsAskingWhenAProbeSaysNothing() async throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        try directory.directory("home/.Trash")
        try directory.setPermissions(0, of: "home/.Trash")
        defer { try? directory.setPermissions(0o755, of: "home/.Trash") }
        try directory.directory("home/Library/Safari")

        #expect(await FullDiskAccess.state(home: home) == .granted)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PEEL_TEST_THIS_MAC"] != nil))
    func thisMacsTrashAnswersTheProbeClearly() async {
        #expect(FullDiskAccess.canList(URL.homeDirectory.appending(path: ".Trash")) != .unknown)
        #expect(await FullDiskAccess.state() != .unknown)
    }

    /// Uses a folder of its own rather than `/Applications`, where write access depends on the account.
    @Test func readsAppManagementFromARemoval() throws {
        let directory = try TemporaryDirectory()
        let bundle = try directory.directory("Applications/Example.app")
        let trashed = TrashResult(trashed: [TrashedItem(originalURL: bundle, trashedURL: URL(filePath: "/Users/x/.Trash/Example.app"), date: .now)])
        #expect(AppManagement.state(after: trashed, appBundles: [bundle]) == .granted)

        let refused = TrashResult(failures: [TrashFailure(url: bundle, reason: .notPermitted)])
        #expect(AppManagement.state(after: refused, appBundles: [bundle]) == .missing)
        #expect(AppManagement.isRefusedForWantOfPermission(bundle), "the removal alert asks the same")

        let other = TrashResult(failures: [TrashFailure(url: bundle, reason: .failed("busy"))])
        #expect(AppManagement.state(after: other, appBundles: [bundle]) == nil)
        #expect(AppManagement.state(after: refused, appBundles: []) == nil)
    }

    /// A bundle locked in Finder is refused with the same error, and turning App Management on changes nothing
    /// for it: Home must not ask for a permission that is not what is missing.
    @Test func aRefusalOfALockedBundleSaysNothing() throws {
        let directory = try TemporaryDirectory()
        let bundle = try directory.directory("Applications/Locked.app")
        let path = bundle.path(percentEncoded: false)
        #expect(chflags(path, UInt32(UF_IMMUTABLE)) == 0)
        defer { chflags(path, 0) }
        #expect(!AppManagement.isRefusedForWantOfPermission(bundle), "the removal alert must not ask for App Management either")

        let refused = TrashResult(failures: [TrashFailure(url: bundle, reason: .notPermitted)])
        #expect(AppManagement.state(after: refused, appBundles: [bundle]) == nil)
    }

    /// A refusal where the account cannot write is about ownership, not App Management.
    @Test(.permissionsHold) func aRefusalInAFolderThatCannotBeWrittenSaysNothing() throws {
        let directory = try TemporaryDirectory()
        let bundle = try directory.directory("Locked/Example.app")
        try directory.setPermissions(0o555, of: "Locked")
        defer { try? directory.setPermissions(0o755, of: "Locked") }

        let refused = TrashResult(failures: [TrashFailure(url: bundle, reason: .notPermitted)])
        #expect(AppManagement.state(after: refused, appBundles: [bundle]) == nil)
    }

    @Test func callsRefusedRemovalsNotPermitted() {
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        #expect(TrashService.reason(for: denied) == .notPermitted)

        let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
        ])
        #expect(TrashService.reason(for: wrapped) == .notPermitted)

        let missing = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        #expect(TrashService.reason(for: missing) != .notPermitted)
    }
}

struct AppManagementTests {
    /// The root helper needs no permission of Peel's, so a bundle it moved proves nothing about App Management.
    @Test func aBundleTheHelperMovedProvesNothing() {
        let bundle = URL(filePath: "/Applications/Example.app", directoryHint: .isDirectory)
        let trashed = TrashResult(trashed: [TrashedItem(originalURL: bundle, trashedURL: bundle, date: .now)])

        #expect(AppManagement.state(after: trashed, appBundles: [bundle]) == .granted)
        #expect(AppManagement.state(after: trashed, appBundles: [bundle], movedByTheHelper: [bundle]) == nil)
    }

    /// A link left by a Peel that is gone, or somebody else's `peel`, is not Peel's tool. It is never counted as
    /// installed, and it is not Peel's to tell anyone to remove.
    @Test func knowsItsOwnCommandLineTool() throws {
        let directory = try TemporaryDirectory()
        let embedded = try directory.file("Peel.app/Contents/Helpers/peel", bytes: 16)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: embedded.path(percentEncoded: false)
        )
        let link = directory.url.appending(path: "peel").path(percentEncoded: false)
        let bundle = directory.url.appending(path: "Peel.app", directoryHint: .isDirectory)
        func standing() -> CommandLineTool.Standing {
            CommandLineTool.standing(at: link, embedded: bundle.appending(path: "Contents/Helpers/peel"))
        }

        #expect(standing() == .missing)
        try FileManager.default.createSymbolicLink(
            atPath: link,
            withDestinationPath: embedded.path(percentEncoded: false)
        )
        #expect(standing() == .installed)

        try FileManager.default.removeItem(atPath: link)
        try FileManager.default.createSymbolicLink(
            atPath: link,
            withDestinationPath: directory.url.appending(path: "Gone.app/Contents/Helpers/peel")
                .path(percentEncoded: false)
        )
        #expect(standing() == .otherPeel, "a link to a Peel that is gone read as installed")

        try FileManager.default.removeItem(atPath: link)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/opt/other/bin/peel")
        #expect(standing() == .somethingElse, "a link to another program read as Peel's")

        try FileManager.default.removeItem(atPath: link)
        let stranger = try directory.file("stranger", bytes: 16)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: stranger.path(percentEncoded: false)
        )
        try FileManager.default.copyItem(atPath: stranger.path(percentEncoded: false), toPath: link)
        #expect(standing() == .somethingElse, "somebody else's executable read as Peel's tool")
    }

    /// `ln -f` deletes what is in the link's place, for good, so it replaces only a link to another Peel's tool,
    /// and Peel offers no command at all where something else is.
    @Test func neverOffersACommandThatReplacesWhatIsNotPeels() throws {
        let embedded = URL(filePath: "/Applications/Peel.app/Contents/Helpers/peel")

        #expect(CommandLineTool.installCommand(embedded: embedded, standing: .missing) == "sudo mkdir -p /usr/local/bin && sudo ln -s '/Applications/Peel.app/Contents/Helpers/peel' /usr/local/bin/peel")
        #expect(CommandLineTool.installCommand(embedded: embedded, standing: .otherPeel) == "sudo mkdir -p /usr/local/bin && sudo ln -sf '/Applications/Peel.app/Contents/Helpers/peel' /usr/local/bin/peel")
        #expect(CommandLineTool.installCommand(embedded: embedded, standing: .somethingElse) == nil)
    }

    /// Installed with Homebrew on a Mac with Apple silicon, the `peel` command is Homebrew's link in
    /// `/opt/homebrew/bin`, not the one Peel offers to make in `/usr/local/bin`. Either one leading to this Peel's
    /// tool means the command is there.
    @Test func findsTheCommandWhereHomebrewLinkedIt() throws {
        let directory = try TemporaryDirectory()
        let embedded = try directory.file("Peel.app/Contents/Helpers/peel", bytes: 16)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: embedded.path(percentEncoded: false)
        )
        let peels = directory.url.appending(path: "usr-local-bin-peel").path(percentEncoded: false)
        let homebrews = directory.url.appending(path: "opt-homebrew-bin-peel").path(percentEncoded: false)
        func isOnThePath() -> Bool {
            CommandLineTool.isOnThePath(embedded: embedded, at: [peels, homebrews])
        }

        #expect(!isOnThePath())
        try FileManager.default.createSymbolicLink(
            atPath: homebrews,
            withDestinationPath: embedded.path(percentEncoded: false)
        )
        #expect(isOnThePath(), "Homebrew's link was not counted")
        #expect(CommandLineTool.paths == ["/usr/local/bin/peel", "/opt/homebrew/bin/peel"])
    }

    /// The install command points to where Peel is, so it is only worth offering where Peel stays. The copy macOS
    /// runs a downloaded app from (App Translocation) is in a new folder every launch and is gone when Peel quits.
    @Test func knowsWhereItIsRunningFrom() {
        let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)
        func place(_ path: String) -> CommandLineTool.Place {
            CommandLineTool.place(of: URL(filePath: path, directoryHint: .isDirectory), home: home)
        }

        #expect(place("/Applications/Peel.app") == .applications)
        #expect(place("/Applications/Utilities/Peel.app") == .applications)
        #expect(place("/Users/me/Applications/Peel.app") == .applications)
        #expect(place("/Users/me/Downloads/Peel.app") == .elsewhere)
        #expect(place("/Volumes/Peel 1.0/Peel.app") == .elsewhere)
        #expect(place("/private/var/folders/x2/abc/d/AppTranslocation/41B9A/d/Peel.app") == .temporaryCopy)

        let command = CommandLineTool.installCommand(embedded: URL(filePath: "/Users/me/Sam's Apps/Peel.app/Contents/Helpers/peel"), standing: .missing)
        #expect(command?.hasSuffix("sudo ln -s '/Users/me/Sam'\\''s Apps/Peel.app/Contents/Helpers/peel' /usr/local/bin/peel") == true)
    }
}
/// The engine that turns "^[1 item](inflect: true)" into "1 item". It corrects a plural noun as well, so both
/// forms work. Peel writes the singular, which is the documented form.
struct InflectionTests {
    @Test func agreesWithTheNumberInFrontOfIt() {
        #expect(String(AttributedString(localized: "^[\(1) item](inflect: true)").characters) == "1 item")
        #expect(String(AttributedString(localized: "^[\(2) item](inflect: true)").characters) == "2 items")
        #expect(String(AttributedString(localized: "^[\(1) items](inflect: true)").characters) == "1 item")
    }
}
