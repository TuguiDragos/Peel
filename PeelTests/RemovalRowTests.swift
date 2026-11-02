import AppKit
@testable import Peel
import SwiftUI
import Testing

@MainActor
struct RemovalRowTests {
    private final class Rows: RowSelection {
        var selectedURLs: Set<URL> = []
    }

    private func height(atWidth width: CGFloat) -> CGFloat {
        let row = RemovalRow(
            url: URL(filePath: "/org.example/file.txt"), icon: .symbol("doc"), detail: nil, kind: "Application",
            size: 1_000, selection: Rows(), isSelected: false
        )
        return NSHostingView(rootView: row.frame(width: width)).fittingSize.height
    }

    @Test func aRowTooNarrowForItsColumnsIsAsTallAsItsSecondLineFromItsFirstLayout() {
        guard #available(macOS 27, *) else { return }
        #expect(height(atWidth: 300) > height(atWidth: 900))
    }
}
