@testable import PeelPrivileged
import Testing

struct PathComponentsTests {
    /// A slash followed by a combining mark is one `Character`, but it still separates two names.
    @Test func splitsAtEverySlash() {
        #expect(PathComponents.of("/Library/Caches/dir/\u{301}x.plist") == ["Library", "Caches", "dir", "\u{301}x.plist"])
        #expect(PathComponents.of("/a//b/") == ["a", "b"])
        #expect(PathComponents.of("/").isEmpty)
    }

    @Test func tellsAPathInsideAFolderFromOneBesideIt() {
        #expect(PathComponents.isPath("/Users/me/Library/Mail/V10/x", atOrInside: "/Users/me/Library/Mail"))
        #expect(PathComponents.isPath("/Users/me/Library/Mail", atOrInside: "/Users/me/Library/Mail/"))
        #expect(!PathComponents.isPath("/Users/me/Library/Mailbox", atOrInside: "/Users/me/Library/Mail"))
        #expect(PathComponents.isPath("/Users/me/Library/Mail/\u{301}x", inside: "/Users/me/Library/Mail"))
        #expect(!PathComponents.isPath("/Users/me/Library/Mail", inside: "/Users/me/Library/Mail"))
        #expect(PathComponents.isPath("/anything", inside: "/"))
    }

    /// The disk treats a composed letter and a letter followed by its mark as one name, and so does the comparison.
    @Test func matchesBothSpellingsOfALetter() {
        #expect(PathComponents.isPath("/Users/me/caf\u{E9}/notes.txt", inside: "/Users/me/cafe\u{301}"))
    }
}
