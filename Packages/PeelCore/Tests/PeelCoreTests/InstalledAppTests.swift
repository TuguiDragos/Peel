import Foundation
@testable import PeelCore
import Testing

struct InstalledAppTests {
    @Test func answersWhetherItIsPeelWithoutWorkingItOutAgain() {
        let app = InstalledApp(url: URL(filePath: "/Applications/Editor.app"), bundleIdentifier: "org.example.editor", name: "Editor")
        var answers = 0

        let took = ContinuousClock().measure {
            for _ in 0..<200_000 where app.isPeelItself { answers += 1 }
        }

        #expect(answers == 0)
        #expect(took < .milliseconds(100))
    }

    @Test func theAppAroundTheRunningCodeIsPeelWhateverItIsCalled() {
        let around = InstalledApp(url: Bundle.main.bundleURL.deletingLastPathComponent(), bundleIdentifier: "org.example.around", name: "Around")

        #expect(around.isPeelItself)
    }
}
