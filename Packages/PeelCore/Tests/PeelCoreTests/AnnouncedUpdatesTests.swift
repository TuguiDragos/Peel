import Foundation
@testable import PeelCore
import Testing

struct AnnouncedUpdatesTests {
    private let editor = InstalledApp(
        url: URL(filePath: "/Applications/Editor.app"), bundleIdentifier: "org.example.editor", name: "Editor"
    )
    private let viewer = InstalledApp(
        url: URL(filePath: "/Applications/Viewer.app"), bundleIdentifier: "org.example.viewer", name: "Viewer"
    )

    @Test func tellsOfEachUpdateOnceWhoeverFoundIt() {
        var versions = ["org.example.editor": "2.0", "org.example.viewer": "5.0"]
        var told = AnnouncedUpdates()

        #expect(told.takeNew([editor], version: { versions[$0.reference] }, whileChecking: true).isEmpty)
        #expect(told.takeNew([editor], version: { versions[$0.reference] }, whileChecking: false) == [editor])
        #expect(told.takeNew([editor, viewer], version: { versions[$0.reference] }, whileChecking: false) == [viewer])
        #expect(told.takeNew([editor, viewer], version: { versions[$0.reference] }, whileChecking: false).isEmpty)

        versions["org.example.editor"] = "2.1"
        let relaunched = AnnouncedUpdates(versions: told.versions)
        var again = relaunched
        #expect(again.takeNew([editor, viewer], version: { versions[$0.reference] }, whileChecking: false) == [editor])
    }
}
