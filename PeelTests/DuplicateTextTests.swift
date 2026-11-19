import Foundation
@testable import Peel
import Testing

struct DuplicateTextTests {
    @Test func theFoldersNoteSaysWhatMakesACopyInAFewSentences() {
        #expect(DuplicateScanForm.foldersNote.key == "Peel compares files by their full contents, and a folder is a copy only when every file in it matches. Repositories, projects, node_modules, and libraries such as Photos are left alone. A copy with its own tags or comment, or one that syncs, is never moved.")
    }
}
