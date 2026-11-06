import AppKit
@testable import Peel
import SwiftUI
import Testing

@MainActor
struct NoProjectFoldersTests {
    @Test func itsButtonsFitTheListColumn() {
        let suggested = ["Developer", "Projects", "Code", "src"].map { URL(filePath: "/Users/Shared/\($0)") }
        let host = NSHostingController(rootView: NoProjectFolders(suggested: suggested, choose: {}, add: { _ in }))
        let column = ListColumn.width

        let size = host.sizeThatFits(in: CGSize(width: column, height: 2_000))

        #expect(size.width <= column)
    }
}
