import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct QuitNamesTests {
    @Test func namesEachProcessOnceAndTheFirstFewOfMany() {
        #expect(QuitBeforeRemoving.named(["Chat", "Chat Helper", "Chat Helper"]) == ["Chat", "Chat Helper"].formatted(.list(type: .and)))
        let many = QuitBeforeRemoving.named(["A", "B", "C", "D", "E", "F"])
        #expect(many == RemovalFailureAlert.listed(["A", "B", "C", "D", "E", "F"]))
        #expect(many.contains("2"))
    }

    @Test func asksToQuitWithTheWordsThatFitWhatGoes() {
        let editor = InstalledApp(
            url: URL(filePath: "/Applications/Editor.app"), bundleIdentifier: "org.example.editor", name: "Editor"
        )
        let viewer = InstalledApp(
            url: URL(filePath: "/Applications/Viewer.app"), bundleIdentifier: "org.example.viewer", name: "Viewer"
        )
        let title = { (apps: [InstalledApp], going: Set<URL>) in
            String(localized: BulkRemovalPlan.quitTitle(running: apps, going: going))
        }

        #expect(title([editor], [editor.url]) == String(localized: "Quit \(editor.name) before removing it."))
        #expect(title([editor], []) == String(localized: "Quit \(editor.name) before removing its files."))
        #expect(title([editor, viewer], [editor.url, viewer.url]) == String(localized: "Quit these apps before removing them."))
        #expect(title([editor, viewer], [editor.url]) == String(localized: "Quit these apps first."))
    }
}
