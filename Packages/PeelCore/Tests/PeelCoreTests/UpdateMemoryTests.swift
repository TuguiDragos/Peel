import Foundation
@testable import PeelCore
import Testing

struct UpdateMemoryTests {
    private func app(_ version: String, build: String = "1", feed: UpdateFeed? = nil) -> InstalledApp {
        InstalledApp(
            url: URL(filePath: "/Applications/Foo.app", directoryHint: .isDirectory),
            bundleIdentifier: "com.example.foo",
            name: "Foo",
            version: version,
            buildVersion: build,
            updateFeed: feed
        )
    }

    private let feed = UpdateFeed.sparkle(URL(string: "https://feed.example.com/appcast.xml")!)

    private func savedByAnEarlierChecker(_ entry: UpdateMemory) throws -> UpdateMemory {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        object.removeValue(forKey: "revision")
        return try JSONDecoder().decode(UpdateMemory.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private let schedule = UpdateSchedule.next(after: .upToDate, following: nil)

    /// An answer is about the build it was given for. If the app updates itself while Peel is closed, the
    /// answer about 1.0 is dropped; kept, it would read "2.0 → 2.0" under Updates Available.
    @Test func forgetsAnAnswerAboutAnotherBuild() {
        let learned = UpdateMemory(
            status: .updateAvailable(version: "2.0"),
            schedule: schedule,
            checked: .now,
            describing: app("1.0")
        )
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
        #expect(
            UpdateMemory.recalled(
                from: memory,
                for: [],
                now: schedule.due.addingTimeInterval(UpdateMemory.longestAbsence + 1)
            ).isEmpty
        )
    }

    @Test func asksAgainAboutAnAppAnEarlierCheckerCouldNotCheck() throws {
        let saved = Data(#"{"com.example.foo":{"status":{"unsupported":{}},"schedule":{"due":814968811,"isRetrying":false,"wait":604800},"checked":814364011,"version":"1.0","buildVersion":"1"}}"#.utf8)
        let earlier = try JSONDecoder().decode([String: UpdateMemory].self, from: saved)
        let now = Date(timeIntervalSinceReferenceDate: 814364011)

        #expect(UpdateMemory.recalled(from: earlier, for: [app("1.0")], now: now).isEmpty)

        let current = ["com.example.foo": UpdateMemory(status: .unsupported, schedule: schedule, checked: now, describing: app("1.0"))]
        #expect(UpdateMemory.recalled(from: current, for: [app("1.0")], now: now) == current)

        let upToDate = try JSONDecoder().decode(
            [String: UpdateMemory].self,
            from: Data(String(decoding: saved, as: UTF8.self).replacingOccurrences(of: "unsupported", with: "upToDate").utf8)
        )
        #expect(UpdateMemory.recalled(from: upToDate, for: [app("1.0", feed: feed)], now: now) == upToDate)
    }

    @Test func forgetsWhatAnEarlierCheckerSaidOfAnAppNobodyIsAskedAbout() throws {
        for status in [UpdateStatus.updateAvailable(version: "2.0"), .upToDate, .failed] {
            let entry = UpdateMemory(status: status, schedule: schedule, checked: .now, describing: app("1.0"))
            let earlier = ["com.example.foo": try savedByAnEarlierChecker(entry)]
            #expect(UpdateMemory.recalled(from: earlier, for: [app("1.0")]).isEmpty, "\(status)")
            #expect(UpdateMemory.recalled(from: earlier, for: [app("1.0", feed: feed)]) == earlier, "\(status)")

            let current = ["com.example.foo": entry]
            #expect(UpdateMemory.recalled(from: current, for: [app("1.0")]) == current, "\(status)")
        }
    }

    /// An entry stored by an earlier version of Peel names no build, so it describes no app, and the app is
    /// checked again.
    @Test func readsAnEntryStoredBeforeBuildsWereKept() throws {
        let stored = try JSONEncoder().encode([
            "com.example.foo": UpdateMemory(status: .upToDate, schedule: schedule, checked: nil, describing: app("1.0"))
        ])
        var object = try #require(JSONSerialization.jsonObject(with: stored) as? [String: [String: Any]])
        object["com.example.foo"]?.removeValue(forKey: "version")
        object["com.example.foo"]?.removeValue(forKey: "buildVersion")

        let old = try JSONDecoder().decode(
            [String: UpdateMemory].self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        #expect(old["com.example.foo"]?.describes(app("1.0")) == false)
    }

    @Test func keepsAcrossLaunchesThatTheAppStoreListedNoSuchApp() throws {
        let entry = UpdateMemory(
            status: .updateAvailable(version: "1.2", source: .appStore), schedule: schedule, checked: nil,
            describing: app("1.0"), isNotListed: true
        )
        let saved = try JSONDecoder().decode(UpdateMemory.self, from: JSONEncoder().encode(entry))
        #expect(saved.isNotListed == true)

        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        object.removeValue(forKey: "isNotListed")
        let earlier = try JSONDecoder().decode(UpdateMemory.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(earlier.isNotListed == nil && earlier.status == entry.status)
    }
}
