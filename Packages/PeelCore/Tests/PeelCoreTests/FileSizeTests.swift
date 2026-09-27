import Foundation
@testable import PeelCore
import Testing

struct FileSizeTests {
    /// A file with several names is one file on the disk, so it is counted once. Adding up every name would
    /// report more than emptying the folder could ever free.
    /// What is measured is looked at by its own name as well as by what is inside it: a wallet's file measured on
    /// its own, a `keystore` folder, and a repository's own folder.
    @Test func theMeasuredItemsOwnNameCounts() async throws {
        let directory = try TemporaryDirectory()
        let wallet = try directory.file("SomeCoin/wallet.dat", bytes: 100)
        let keys = try directory.file("Monero/mine.keys", bytes: 100)
        let keystore = try directory.file("Ethereum/keystore/key", bytes: 100).deletingLastPathComponent()
        let repository = try directory.file("project/.hg/store/data", bytes: 100).deletingLastPathComponent().deletingLastPathComponent()
        let plain = try directory.file("Notes/notes.txt", bytes: 100)

        #expect(await FileSize.contents(of: wallet)?.holdsWallet == true)
        #expect(await FileSize.contents(of: keys)?.holdsWallet == true)
        #expect(await FileSize.contents(of: keystore)?.holdsWallet == true)
        #expect(await FileSize.contents(of: repository)?.holdsRepository == true)
        #expect(await FileSize.contents(of: plain).map { $0.holdsWallet || $0.holdsRepository } == false)
    }

    @Test func countsAFileWithSeveralNamesOnce() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("tree")
        let original = try directory.file("tree/original.bin", bytes: 400_000)

        for name in ["second.bin", "third.bin", "fourth.bin"] {
            try FileManager.default.linkItem(at: original, to: folder.appending(path: name))
        }

        let size = try #require(await FileSize.allocatedSize(of: folder))
        let one = try #require(await FileSize.allocatedSize(of: original))

        #expect(one > 0)
        #expect(size == one, "four names for one file measured \(size) instead of \(one)")
    }

    /// A walk releases what it reads as it goes, rather than holding every name until it ends. The check runs in
    /// a process of its own: the footprint covers the whole process, and suites running in parallel would add
    /// their own allocations to it.
    @Test func aWalkLetsGoOfWhatItReadAsItGoes() async {
        await #expect(processExitsWith: .success, "eight walks of 8,000 entries held what they read until their caller let go") {
            if try FileSizeTests.heldByEightWalks() >= 12 << 20 {
                exit(EXIT_FAILURE)
            }
        }
    }

    /// Returns how much more memory the process holds after eight walks, before their autorelease pool drains.
    private static func heldByEightWalks() throws -> UInt64 {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("tree")
        for index in 0..<8_000 {
            FileManager.default.createFile(atPath: folder.appending(path: "file-\(index)").path, contents: nil)
        }
        let before = footprint()
        var held: UInt64 = 0
        autoreleasepool {
            for _ in 0..<8 {
                _ = FileSize.walk(folder, unless: { false })
            }
            let after = footprint()
            held = after > before ? after - before : 0
        }
        return held
    }

    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.phys_footprint : 0
    }

    @Test func stillAddsUpSeparateFiles() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("tree")
        try directory.file("tree/a.bin", bytes: 100_000)
        try directory.file("tree/b.bin", bytes: 100_000)

        #expect(try #require(await FileSize.allocatedSize(of: folder)) >= 200_000)
    }

    /// A folder macOS will not open has no known size. Read as zero, it would fall under Space's size floor and
    /// never be shown.
    @Test func knowsNoSizeForAFolderItCannotOpen() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("closed")
        try directory.file("closed/a.bin", bytes: 100_000)
        try directory.setPermissions(0, of: "closed")
        defer { try? directory.setPermissions(0o755, of: "closed") }

        #expect(await FileSize.contents(of: folder)?.couldNotBeRead == true)
        #expect(await FileSize.allocatedSize(of: folder) == nil)
    }

    /// An item whose own attributes macOS will not give, because the folder around it cannot be searched, is not
    /// known either, and never reads as zero. An item that is not there at all holds nothing.
    @Test func knowsNoSizeForAnItemItCannotLookAt() async throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("closed/a.bin", bytes: 100_000)
        let folder = try directory.directory("closed/inner")
        try directory.file("closed/inner/b.bin", bytes: 100_000)
        try directory.setPermissions(0, of: "closed")
        defer { try? directory.setPermissions(0o755, of: "closed") }

        #expect(await FileSize.allocatedSize(of: file) == nil)
        #expect(await FileSize.allocatedSize(of: folder) == nil)
        #expect(await FileSize.contents(of: file)?.couldNotBeRead == true)
        #expect(await FileSize.allocatedSize(of: directory.url.appending(path: "not there")) == 0)
    }

    /// `allocatedSize(of:)` makes the same walk as `contents(of:)`, so both report the same size.
    @Test func measuresAFolderThatAnswers() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("tree")
        try directory.file("tree/a.bin", bytes: 100_000)

        let measured = try #require(await FileSize.allocatedSize(of: folder))
        #expect(measured >= 100_000)
        #expect(await FileSize.contents(of: folder)?.size == measured)
    }

    /// The budget is not checked against the clock: the suites run in parallel, so this task can resume many
    /// seconds late through no fault of the code under test.
    @Test func comesBackFromAFolderTooBigForItsBudget() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("wide")
        for index in 0..<200 {
            try directory.file("wide/folder\(index)/file.bin", bytes: 4_096)
        }

        let measured = await FileSize.allocatedSize(of: folder, within: 0.001)

        // Either it finished, or it ran out of budget. Never a hang, and never a wrong number.
        if let measured { #expect(measured >= 4_096) }
    }

    /// A folder that is only big runs out of budget like a wedged one, but its walk does finish. The answer is
    /// kept for whoever asks next, so the folder does not stay unknown until Peel is relaunched.
    @Test func aWalkThatFinishesLateAnswersTheNextQuestion() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("big")
        try directory.file("big/a.bin", bytes: 8_192)
        for index in 0..<300 {
            try directory.file("big/folder\(index)/file.bin", bytes: 16)
        }

        #expect(await FileSize.allocatedSize(of: folder, within: 0) == nil, "no budget at all, so nothing can be known yet")
        var later: Int64?
        for _ in 0..<200 where later == nil {
            try await Task.sleep(for: .milliseconds(20))
            later = await FileSize.allocatedSize(of: folder, within: 0)
        }
        #expect(await FileSize.contents(of: folder)?.size == later)
        #expect(try #require(later) >= 8_192)
    }

    /// A canceled question comes back at once with nothing. That says nothing about the folder, so it is not
    /// marked as one that never answers, and the next question gets the real size.
    @Test func aQuestionThatWasWithdrawnBlamesNothingOnTheFolder() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("tree")
        try directory.file("tree/a.bin", bytes: 100_000)

        let task = Task { () -> Int64? in
            while !Task.isCancelled { await Task.yield() }
            return await FileSize.allocatedSize(of: folder, within: 3_600)
        }
        task.cancel()

        #expect(await task.value == nil, "nobody wanted it, so nothing was walked for it")
        #expect(try #require(await FileSize.allocatedSize(of: folder)) >= 100_000)
    }

    /// A walk nobody wants anymore stops at the next entry instead of reading the folder to its end.
    @Test func aWalkNobodyWantsStopsWhereItIs() throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("tree")
        for index in 0..<50 {
            try directory.file("tree/\(index).bin", bytes: 1_000)
        }

        #expect(FileSize.walk(folder, unless: { true }) == nil)
        #expect(try #require(FileSize.walk(folder, unless: { false })).size >= 50_000)
    }

    /// Two pages can ask about one folder at once (Space and an app's page both measure a cache). They wait
    /// for one walk and both get its answer.
    @Test func twoQuestionsAboutOneFolderGetTheSameAnswer() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("tree")
        try directory.file("tree/a.bin", bytes: 100_000)

        async let first = FileSize.allocatedSize(of: folder)
        async let second = FileSize.allocatedSize(of: folder)
        let (one, two) = (await first, await second)

        #expect(try #require(one) >= 100_000)
        #expect(one == two)
    }

    /// A folder that did not answer in time is not walked a second time, so its budget is paid only once.
    @Test func doesNotPayTheBudgetTwiceForTheSameFolder() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("tree")
        // Wide enough that a walk cannot finish in no time at all, which is what makes the first answer unknown.
        for index in 0..<300 {
            try directory.file("tree/folder\(index)/file.bin", bytes: 16)
        }

        #expect(await FileSize.allocatedSize(of: folder, within: 0) == nil, "no budget at all, so nothing can be known yet")

        // Asked again, with a real budget: the answer comes from what is known about the folder, not from a
        // second walk waited out. The same folder written with a trailing slash is the same key.
        let withSlash = URL(filePath: folder.path(percentEncoded: false) + "/", directoryHint: .isDirectory)
        let start = ContinuousClock.now
        _ = await FileSize.allocatedSize(of: folder, within: FileSize.budget)
        _ = await FileSize.allocatedSize(of: withSlash, within: FileSize.budget)
        #expect(ContinuousClock.now - start < .seconds(2), "a question about a folder already being walked paid a budget of its own")
    }

    /// The walk that measures a folder also says whether a repository is in it, at any depth, because that
    /// is what stops the folder being selected for removal on the user's behalf.
    @Test func reportsARepositoryFoundAtAnyDepth() async throws {
        let directory = try TemporaryDirectory()
        let plain = try directory.directory("plain")
        try directory.file("plain/a/b/c/notes.txt")
        let holding = try directory.directory("holding")
        try directory.file("holding/a/b/c/project/.git/HEAD")

        #expect(await FileSize.contents(of: plain)?.holdsRepository == false)
        #expect(await FileSize.contents(of: holding)?.holdsRepository == true)
    }

    /// Git is not the only one: a Mercurial, Subversion, or Jujutsu working copy can also hold work that exists
    /// nowhere else.
    @Test func reportsEveryKindOfRepository() async throws {
        let directory = try TemporaryDirectory()
        for marker in [".git", ".hg", ".svn", ".jj"] {
            let folder = try directory.directory("holding\(marker)")
            try directory.file("holding\(marker)/project/\(marker)/HEAD")
            #expect(await FileSize.contents(of: folder)?.holdsRepository == true, "\(marker) was not seen")
        }
    }

    /// The same walk reports a wallet or a signing key inside. A Homebrew cask can name a coin app's whole data
    /// folder, and the keys are in it.
    @Test func reportsAWalletFoundAtAnyDepth() async throws {
        let directory = try TemporaryDirectory()
        let plain = try directory.directory("plain")
        try directory.file("plain/a/b/notes.txt")
        let core = try directory.directory("core")
        try directory.file("core/wallet.dat", bytes: 64)
        let electrum = try directory.directory("electrum")
        try directory.file("electrum/wallets/default_wallet")
        let bisq = try directory.directory("bisq")
        try directory.file("bisq/btc_mainnet/wallet/bisq_BTC.wallet")
        let android = try directory.directory("android")
        try directory.file("android/keystore/release")

        #expect(await FileSize.contents(of: plain)?.holdsWallet == false)
        for folder in [core, electrum, bisq, android] {
            #expect(await FileSize.contents(of: folder)?.holdsWallet == true, "\(folder.lastPathComponent) reads as holding no wallet")
        }
    }

    /// The names wallets and their keys go by, as each project's documentation or source gives them, and names
    /// that only look close.
    @Test func knowsTheNamesWalletsAndTheirKeysGoBy() {
        let wallets = [
            "wallet.dat", "zingo-wallet.dat", "wallets", "wallets2", "keystore", "keystores", "bisq_BTC.wallet",
            "exodus.wallet", "mine.keys", "account.mmdbdoc_v1", "hsm_secret", "emergency.recover", "channel.backup",
            "seed.dat", "wallet.seed", "mnemonics", "keyring-file", "keyring-test", "priv_validator_key.json",
            "sui.keystore", "sqlite_wallets", "encryption-identity.txt", ".aptos", "Wallet.DAT",
        ]
        for name in wallets {
            #expect(FileSize.isWallet(name), "\(name) was not read as a wallet")
        }
        for name in ["notes.txt", "keys", "wallet.datx", "seed.txt", "keystore.txt", "Wallets.app", ".bitmonero"] {
            #expect(!FileSize.isWallet(name), "\(name) was read as a wallet")
        }
    }

    /// A folder whose contents are only in the cloud is skipped: listing it fetches the whole tree from the
    /// provider and adds nothing, since it holds no local bytes. Ordinary folders are not dataless.
    @Test func doesNotWalkIntoAFolderThatIsOnlyInTheCloud() throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("plain")
        try directory.file("plain/file.txt")

        #expect(!FileSize.isDataless(folder))
        #expect(!FileSize.isDataless(directory.url.appending(path: "missing")))
    }

    /// A folder's own date says nothing about a file rewritten deep inside it, so the walk checks the date of
    /// every entry it passes.
    @Test func reportsTheNewestWriteFoundAtAnyDepth() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("support")
        let log = try directory.file("support/logs/agent.log")
        let lastYear = Date(timeIntervalSinceNow: -365 * 24 * 60 * 60)
        let lastMonth = Date(timeIntervalSinceNow: -30 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: lastMonth], ofItemAtPath: log.path(percentEncoded: false))
        for old in [log.deletingLastPathComponent(), folder] {
            try FileManager.default.setAttributes([.modificationDate: lastYear], ofItemAtPath: old.path(percentEncoded: false))
        }

        let newest = try #require(await FileSize.contents(of: folder)?.newestChange)

        #expect(abs(newest.timeIntervalSince(lastMonth)) < 1)
    }

}
