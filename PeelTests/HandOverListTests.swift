import AppKit
@testable import Peel
import Testing

@MainActor
struct HandOverListTests {
    /// Unicode allows no break before a period, even after a space, so a list of extensions broke inside one.
    @Test func aKindWithManyExtensionsBreaksBetweenThem() {
        let extensions = (1...24).map { String(format: ".kd%02d", $0) }
        let name = HandOverList.breakable("Probe Document (\(extensions.joined(separator: ", ")))")
        let storage = NSTextStorage(string: name, attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 312, height: 10_000))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)

        var starts: [String] = []
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, glyphs, _ in
            let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            starts.append(String((name as NSString).substring(with: characters).prefix(1)))
        }

        #expect(starts.count > 1)
        #expect(starts.dropFirst().allSatisfy { $0 == "." }, "\(starts)")
    }
}
