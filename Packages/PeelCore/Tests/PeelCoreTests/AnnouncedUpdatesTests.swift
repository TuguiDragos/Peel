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
        func new(_ waiting: [InstalledApp], whileChecking: Bool = false) -> [InstalledApp] {
            told.takeNew(waiting, version: { versions[$0.reference] }, whileChecking: whileChecking, checksAreOn: true)
        }

        #expect(new([editor], whileChecking: true).isEmpty)
        #expect(new([editor]) == [editor])
        #expect(new([editor, viewer]) == [viewer])
        #expect(new([editor, viewer]).isEmpty)

        versions["org.example.editor"] = "2.1"
        var again = AnnouncedUpdates(versions: told.versions)
        let relaunched = again.takeNew(
            [editor, viewer], version: { versions[$0.reference] }, whileChecking: false, checksAreOn: true
        )
        #expect(relaunched == [editor])
    }

    @Test func tellsOfNothingWhileTheChecksAreOffAndOfWhatWaitsOnceTheyAreOn() {
        let versions = ["org.example.editor": "2.0", "org.example.viewer": "5.0"]
        let version = { (app: InstalledApp) in versions[app.reference] }
        var told = AnnouncedUpdates()

        let whileOff = told.takeNew([editor], version: version, whileChecking: false, checksAreOn: false)
        let onceOn = told.takeNew([editor], version: version, whileChecking: false, checksAreOn: true)
        told.note([viewer], version: version)
        let noted = told.takeNew([viewer], version: version, whileChecking: false, checksAreOn: true)

        #expect(whileOff.isEmpty)
        #expect(onceOn == [editor])
        #expect(noted.isEmpty, "an update noted as told is not told again")
    }
}
