import Darwin
import Foundation
@testable import PeelCore
import Testing

struct DigestMemoryTests {
    private func randomData(count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }

    private func scan(_ directory: borrowing TemporaryDirectory, memory: DigestMemory) async throws -> DuplicateScan {
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        return try await DuplicateFinder(homeDirectory: home, digestMemory: memory).scan(DuplicateScanOptions(folders: [home]))
    }

    private func names(_ scan: DuplicateScan) -> [[String]] {
        scan.groups.map { $0.files.map { $0.url.pathComponents.drop { $0 != "home" }.dropFirst().joined(separator: "/") } }
    }

    private func digest(_ byte: UInt8) -> ContentDigest {
        ContentDigest(bytes: [UInt8](repeating: byte, count: 32))!
    }

    /// Creates two files of the same size with different bytes. Only a remembered digest that is trusted can
    /// make them match.
    private func twoDifferentFiles(in directory: borrowing TemporaryDirectory) throws -> (URL, URL) {
        let length = FileDigest.sampleLength * 4
        return (
            try directory.file("home/Documents/first.bin", contents: randomData(count: length)),
            try directory.file("home/Documents/second.bin", contents: randomData(count: length))
        )
    }

    private func remember(_ digest: ContentDigest, for urls: [URL], in memory: DigestMemory) throws {
        let known = memory.load()
        for url in urls {
            let identity = try #require(FileIdentity.of(url))
            known.keep(sample: digest, of: identity)
            known.keep(full: digest, of: identity)
        }
        memory.save(known)
    }

    @Test func aScanRemembersWhatItRead() async throws {
        let directory = try TemporaryDirectory()
        let memory = DigestMemory(url: directory.url.appending(path: "digests.bin"))
        let contents = randomData(count: FileDigest.sampleLength * 4)
        let first = try directory.file("home/Documents/first.bin", contents: contents)
        let second = try directory.file("home/Pictures/second.bin", contents: contents)

        #expect(names(try await scan(directory, memory: memory)).map(Set.init) == [["Documents/first.bin", "Pictures/second.bin"]])

        let known = memory.load()
        for url in [first, second] {
            let identity = try #require(FileIdentity.of(url))
            #expect(known.sample(of: identity) == FileDigest.sample(of: url, identity: identity))
            #expect(known.full(of: identity) == FileDigest.full(of: url, identity: identity))
        }
    }

    /// A remembered digest of a file that has not changed is trusted, so the file is not read again.
    @Test func believesWhatItRemembersOfAFileThatIsStillTheSame() async throws {
        let directory = try TemporaryDirectory()
        let memory = DigestMemory(url: directory.url.appending(path: "digests.bin"))
        let (first, second) = try twoDifferentFiles(in: directory)
        try remember(digest(7), for: [first, second], in: memory)

        #expect(names(try await scan(directory, memory: memory)).map(Set.init) == [["Documents/first.bin", "Documents/second.bin"]])
    }

    /// A file rewritten in place and given its old dates back, as a sync tool does, keeps its size and
    /// modification time. Only its status change time shows the write, since nothing can set that one back.
    @Test func readsAgainAFileWrittenSinceEvenUnderItsOldDate() async throws {
        let directory = try TemporaryDirectory()
        let memory = DigestMemory(url: directory.url.appending(path: "digests.bin"))
        let (first, second) = try twoDifferentFiles(in: directory)
        try remember(digest(7), for: [first, second], in: memory)

        let path = second.path(percentEncoded: false)
        let before = try #require(FileIdentity.of(second))
        var original = stat()
        #expect(lstat(path, &original) == 0)
        let handle = try FileHandle(forWritingTo: second)
        try handle.write(contentsOf: randomData(count: 4_096))
        try handle.close()
        var times = [original.st_atimespec, original.st_mtimespec]
        #expect(utimensat(AT_FDCWD, path, &times, 0) == 0)
        let after = try #require(FileIdentity.of(second))
        #expect(after.link == before.link && after.size == before.size && after.modificationTime == before.modificationTime)

        #expect(names(try await scan(directory, memory: memory)).isEmpty)
    }

    @Test func forgetsWhatWasUsedLeastRecentlyPastItsLimit() throws {
        let directory = try TemporaryDirectory()
        let memory = DigestMemory(url: directory.url.appending(path: "digests.bin"), limit: 2)
        var identities: [FileIdentity] = []
        for (index, day) in [30.0, 10, 20].enumerated() {
            let url = try directory.file("file\(index).bin", contents: randomData(count: 100))
            let identity = try #require(FileIdentity.of(url))
            identities.append(identity)
            let known = memory.load(now: Date(timeIntervalSinceReferenceDate: day * 86_400))
            known.keep(sample: digest(UInt8(index)), of: identity)
            memory.save(known)
        }

        let known = memory.load()
        #expect(known.sample(of: identities[0]) == digest(0))
        #expect(known.sample(of: identities[1]) == nil)
        #expect(known.sample(of: identities[2]) == digest(2))
    }

    /// The app and `peel` can scan at once, so each adds what it learned to the file instead of writing over it.
    @Test func keepsWhatTwoScansLearnedAtOnce() throws {
        let directory = try TemporaryDirectory()
        let memory = DigestMemory(url: directory.url.appending(path: "digests.bin"))
        let one = try #require(FileIdentity.of(try directory.file("one.bin", contents: randomData(count: 100))))
        let other = try #require(FileIdentity.of(try directory.file("other.bin", contents: randomData(count: 100))))

        let first = memory.load()
        let second = memory.load()
        first.keep(sample: digest(1), of: one)
        second.keep(sample: digest(2), of: other)
        memory.save(first)
        memory.save(second)

        let known = memory.load()
        #expect(known.sample(of: one) == digest(1))
        #expect(known.sample(of: other) == digest(2))
    }

    /// The memory only saves time, so a file that makes no sense is started again rather than trusted. Here the
    /// damage would make two different files read as the same one.
    @Test func startsAgainFromAFileThatMakesNoSense() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "digests.bin")
        let memory = DigestMemory(url: url)
        let (first, second) = try twoDifferentFiles(in: directory)
        try remember(digest(7), for: [first], in: memory)
        try remember(digest(8), for: [second], in: memory)
        var damaged = try Data(contentsOf: url)
        while let range = damaged.range(of: Data(digest(8).bytes)) {
            damaged.replaceSubrange(range, with: digest(7).bytes)
        }
        try damaged.write(to: url)

        #expect(names(try await scan(directory, memory: memory)).isEmpty)
        let identity = try #require(FileIdentity.of(first))
        #expect(memory.load().sample(of: identity) == FileDigest.sample(of: first, identity: identity))
    }
}
