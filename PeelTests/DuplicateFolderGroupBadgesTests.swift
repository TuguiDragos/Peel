import AppKit
@testable import Peel
@testable import PeelCore
import SwiftUI
import Testing

@MainActor
struct DuplicateFolderGroupBadgesTests {
    @Test func badgesThatDontFitOnOneLineMoveToTheNextRatherThanBeCut() {
        let folders = ["a", "b"].map { name in
            DuplicateFolder(
                url: URL(filePath: "/org.example/\(name)"), fileCount: 12_345, size: 1_234_567_890,
                reclaimableSize: 1_234_567_890, contents: "", neverProjects: []
            )
        }
        let badges = DuplicateFolderGroupBadges(group: DuplicateFolderGroup(id: "org.example", folders: folders))
        let oneLine = NSHostingView(rootView: badges).fittingSize
        let narrower = NSHostingView(rootView: badges.frame(width: oneLine.width - 1)).fittingSize
        #expect(narrower.height > oneLine.height)
    }
}
