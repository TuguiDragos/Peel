import Darwin
import Foundation
@testable import PeelCore
import Testing

/// Most of what Peel reads was written by somebody else and sits in somebody else's bundle, so how big it is
/// was their decision, not Peel's.
struct BoundedReadTests {
    @Test func readsAFileOfAReasonableSize() throws {
        let directory = try TemporaryDirectory()
        let url = try directory.file("small.plist", bytes: 1_024)

        #expect(BoundedRead.data(at: url)?.count == 1_024)
    }

    /// A read that fails partway gives part of the file, which is not the file, so nothing is returned: a
    /// property list cut short can still parse as a smaller one.
    @Test func aReadThatFailsPartwayGivesNothing() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("job.plist", bytes: 100_000)
        var reads = 0
        let failsAfterTheFirstRead: BoundedRead.Read = { descriptor, buffer, count in
            reads += 1
            guard reads == 1 else {
                errno = EIO
                return -1
            }
            return Darwin.read(descriptor, buffer, count)
        }

        #expect(BoundedRead.data(at: file, read: failsAfterTheFirstRead) == nil)
        #expect(BoundedRead.data(at: file)?.count == 100_000)
    }

    @Test func refusesAFileTooBigToBeWhatItClaims() throws {
        let directory = try TemporaryDirectory()
        let url = try directory.file("huge.plist", bytes: 4_096)

        #expect(BoundedRead.data(at: url, maximum: 1_024) == nil)
        #expect(BoundedRead.propertyList(at: url, maximum: 1_024) == nil)
    }

    @Test func refusesAnythingThatIsNotAPlainFile() throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("folder")

        #expect(BoundedRead.data(at: folder) == nil)
        #expect(BoundedRead.data(at: directory.url.appending(path: "missing")) == nil)
    }

    /// A link is read through, and what it leads to is held to the same rules as a file sitting there.
    @Test func readsThroughALinkAndBoundsWhatItLeadsTo() throws {
        let directory = try TemporaryDirectory()
        let small = try directory.file("dotfiles/agent.plist", bytes: 1_024)
        let huge = try directory.file("dotfiles/huge.plist", bytes: 4_096)
        let folder = try directory.directory("dotfiles/folder")
        let links = try directory.directory("LaunchAgents")
        for (name, target) in [("small", small), ("huge", huge), ("folder", folder), ("dangling", directory.url.appending(path: "nothing"))] {
            try FileManager.default.createSymbolicLink(at: links.appending(path: name), withDestinationURL: target)
        }

        #expect(BoundedRead.data(at: links.appending(path: "small"))?.count == 1_024)
        #expect(BoundedRead.data(at: links.appending(path: "huge"), maximum: 1_024) == nil)
        #expect(BoundedRead.data(at: links.appending(path: "folder")) == nil)
        #expect(BoundedRead.data(at: links.appending(path: "dangling")) == nil)
    }

    /// An app whose Info.plist is enormous is skipped rather than read into memory.
    @Test func anAppWithAnEnormousInfoPlistIsNotInspected() throws {
        let directory = try TemporaryDirectory()
        let bundle = directory.url.appending(path: "Huge.app")
        try directory.file("Huge.app/Contents/Info.plist", bytes: BoundedRead.maximumBytes + 1)

        #expect(AppInspector.inspect(bundle) == nil)
    }
}
