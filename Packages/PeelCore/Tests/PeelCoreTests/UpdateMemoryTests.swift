import Foundation
@testable import PeelCore
import Testing

struct UpdateMemoryTests {
    private func app(_ version: String, build: String = "1") -> InstalledApp {
        InstalledApp(url: URL(filePath: "/Applications/Foo.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.foo", name: "Foo", version: version, buildVersion: build)
    }

    private let schedule = UpdateSchedule.next(after: .upToDate, following: nil)

    /// An answer is about the build it was given for. If the app updates itself while Peel is closed, the
    /// answer about 1.0 is dropped; kept, it would read "2.0 → 2.0" under Updates Available.
    @Test func forgetsAnAnswerAboutAnotherBuild() {
        let learned = UpdateMemory(status: .updateAvailable(version: "2.0"), schedule: schedule, checked: .now, describing: app("1.0"))
        let memory = ["com.example.foo": learned]

        #expect(UpdateMemory.recalled(from: memory, for: [app("1.0")]) == memory)
        #expect(UpdateMemory.recalled(from: memory, for: [app("2.0")]).isEmpty)
        #expect(UpdateMemory.recalled(from: memory, for: [app("1.0", build: "2")]).isEmpty)
    }

    /// Two copies of one app can sit at two builds, and an entry describes one of them. It is kept while either
    /// copy is still that build: dropped, the app would be due again at every refresh of the list, and checked
    /// outside its schedule each time.
    @Test func keepsAnEntryWhileOneOfTwoCopiesIsTheBuildItDescribes() {
        let learned = UpdateMemory(status: .upToDate, schedule: schedule, checked: .now, describing: app("1.0"))
        let memory = ["com.example.foo": learned]
        let second = InstalledApp(
            url: URL(filePath: "/Users/x/Applications/Foo.app", directoryHint: .isDirectory),
            bundleIdentifier: "com.example.foo", name: "Foo", version: "2.0", buildVersion: "1"
        )

        #expect(UpdateMemory.recalled(from: memory, for: [app("1.0"), second]) == memory)
        #expect(UpdateMemory.recalled(from: memory, for: [second]).isEmpty)
    }

    /// An app that is not installed right now keeps its entry, since it may be on a disk that is not connected.
    /// The entry goes once it has been due for `UpdateMemory.longestAbsence`, so the list does not keep every app
    /// ever seen.
    @Test func keepsWhatItKnowsAboutAnAppThatIsAwayForAWhile() {
        let learned = UpdateMemory(status: .upToDate, schedule: schedule, checked: .now, describing: app("1.0"))
        let memory = ["com.example.foo": learned]

        #expect(UpdateMemory.recalled(from: memory, for: [], now: schedule.due).count == 1)
        #expect(UpdateMemory.recalled(from: memory, for: [], now: schedule.due.addingTimeInterval(UpdateMemory.longestAbsence + 1)).isEmpty)
    }

    /// An entry stored by an earlier version of Peel names no build, so it describes no app, and the app is
    /// checked again.
    @Test func readsAnEntryStoredBeforeBuildsWereKept() throws {
        let stored = try JSONEncoder().encode(["com.example.foo": UpdateMemory(status: .upToDate, schedule: schedule, checked: nil, describing: app("1.0"))])
        var object = try #require(JSONSerialization.jsonObject(with: stored) as? [String: [String: Any]])
        object["com.example.foo"]?.removeValue(forKey: "version")
        object["com.example.foo"]?.removeValue(forKey: "buildVersion")

        let old = try JSONDecoder().decode([String: UpdateMemory].self, from: JSONSerialization.data(withJSONObject: object))

        #expect(old["com.example.foo"]?.describes(app("1.0")) == false)
    }
}
