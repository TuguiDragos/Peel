import Foundation
@testable import PeelCore
import Testing

struct TimeMachineExclusionTests {
    /// Returns whether, within 2 seconds, the excluded folders among `urls` become exactly `expected`. Right
    /// after the call that sets the mark, and more so under load, a read can still show the old state.
    private func settles(_ urls: [URL], as expected: Set<URL>) async throws -> Bool {
        for _ in 0..<100 where TimeMachineExclusion.excluded(among: urls) != expected {
            try await Task.sleep(for: .milliseconds(20))
        }
        return TimeMachineExclusion.excluded(among: urls) == expected
    }

    /// What each folder reads as, what its parent reads as, and whether the mark is still on the disk, so a failure
    /// says which of them kept the old state.
    private func state(of urls: [URL]) -> String {
        urls.map { url in
            let mark = getxattr(url.path(percentEncoded: false), "com.apple.metadata:com_apple_backup_excludeItem", nil, 0, 0, 0)
            let parent = TimeMachineExclusion.standing(of: url.deletingLastPathComponent())
            return "\(url.lastPathComponent): \(TimeMachineExclusion.standing(of: url)), parent \(parent), mark \(mark >= 0)"
        }.joined(separator: "; ")
    }

    /// The mark is an attribute on the folder, so it goes on and comes off without administrator rights. The
    /// temporary folder works for this test: `tmutil isexcluded "$TMPDIR"` prints `[Excluded]`, yet
    /// `CSBackupIsItemExcluded` answers false for a folder inside it.
    @Test func marksAFolderAndTakesTheMarkOffAgain() async throws {
        let directory = try TemporaryDirectory()
        let modules = try directory.directory("app/node_modules")
        let build = try directory.directory("app/.build")

        #expect(!TimeMachineExclusion.isExcluded(modules))
        #expect(TimeMachineExclusion.setExcluded(true, [modules, build]).isEmpty, "a folder refused the mark")
        #expect(try await settles([modules, build], as: [modules, build]), "\(state(of: [modules, build]))")
        #expect(TimeMachineExclusion.standing(of: modules) == .excludedItself)

        #expect(TimeMachineExclusion.setExcluded(false, [modules]).isEmpty)
        #expect(try await settles([modules, build], as: [build]), "\(state(of: [modules, build]))")
        // A folder inside an excluded folder is excluded from above, not by a mark of its own.
        #expect(TimeMachineExclusion.standing(of: try directory.directory("app/.build/inner")) == .excludedFromAbove)

        #expect(TimeMachineExclusion.setExcluded(false, [build]).isEmpty)
        #expect(try await settles([modules, build], as: []), "\(state(of: [modules, build]))")
    }

    @Test func answersWithoutComplainingForAnEmptyListOrAMissingFolder() throws {
        let directory = try TemporaryDirectory()
        let missing = directory.url.appending(path: "nothing-here")

        #expect(TimeMachineExclusion.excluded(among: []).isEmpty)
        #expect(TimeMachineExclusion.setExcluded(true, []).isEmpty)
        #expect(TimeMachineExclusion.setExcluded(true, [missing]) == [missing], "a folder that is not there took the mark")
        #expect(!TimeMachineExclusion.isExcluded(missing))
    }

    @Test func triesEveryFolderEvenAfterOneRefuses() async throws {
        let directory = try TemporaryDirectory()
        let missing = directory.url.appending(path: "nothing-here")
        let real = try directory.directory("app/node_modules")

        #expect(TimeMachineExclusion.setExcluded(true, [missing, real]) == [missing])
        #expect(try await settles([real], as: [real]))
        _ = TimeMachineExclusion.setExcluded(false, [real])
    }
}
