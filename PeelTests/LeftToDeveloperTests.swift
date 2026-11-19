import Foundation
@testable import Peel
import PeelCore
import Testing

struct LeftToDeveloperTests {
    @Test func theTitleSaysWhatDeveloperToolsHoldOncePeelKnows() {
        #expect(SpaceDetailView.developerTitle(SizeTotal([nil, nil])).key == "Part of this folder belongs to developer tools")
        #expect(SpaceDetailView.developerTitle(SizeTotal([376_000_000])).key == "%@ of this folder belongs to developer tools")
        #expect(
            SpaceDetailView.developerTitle(SizeTotal([376_000_000, nil])).key
                == "%@ of this folder belongs to developer tools"
        )
    }

    @Test func copyDetailsHoldsEveryFolderWithItsSizeWhenKnown() {
        let tools = URL(filePath: "/Library/Caches/org.example.tools", directoryHint: .isDirectory)
        let builds = URL(filePath: "/Library/Caches/org.example.builds", directoryHint: .isDirectory)

        let details = FolderListPopover.details(of: [tools, builds], sizes: [tools: 376_000_000])

        #expect(details == "\(String(localized: "\(tools.abbreviatedPath) (\(Int64(376_000_000).byteCount))"))\n\(builds.abbreviatedPath)")
    }
}
