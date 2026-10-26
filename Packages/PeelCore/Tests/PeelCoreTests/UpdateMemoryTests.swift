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

        #expect(UpdateMemories(memory).recalled(for: [app("1.0")]) == UpdateMemories(memory))
        #expect(UpdateMemories(memory).recalled(for: [app("2.0")]).isEmpty)
        #expect(UpdateMemories(memory).recalled(for: [app("1.0", build: "2")]).isEmpty)
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

        #expect(UpdateMemories(memory).recalled(for: [app("1.0"), second]) == UpdateMemories(memory))
        #expect(UpdateMemories(memory).recalled(for: [second]).isEmpty)
    }

    /// An app that is not installed right now keeps its entry, since it may be on a disk that is not connected.
    /// The entry goes once it has been due for `UpdateMemory.longestAbsence`, so the list does not keep every app
    /// ever seen.
    @Test func keepsWhatItKnowsAboutAnAppThatIsAwayForAWhile() {
        let learned = UpdateMemory(status: .upToDate, schedule: schedule, checked: .now, describing: app("1.0"))
        let memory = ["com.example.foo": learned]

        let later = schedule.due.addingTimeInterval(UpdateMemory.longestAbsence + 1)
        #expect(UpdateMemories(memory).recalled(for: [], now: schedule.due) == UpdateMemories(memory))
        #expect(UpdateMemories(memory).recalled(for: [], now: later).isEmpty)
    }

    @Test func asksAgainAboutAnAppAnEarlierCheckerCouldNotCheck() throws {
        let saved = Data(#"{"com.example.foo":{"status":{"unsupported":{}},"schedule":{"due":814968811,"isRetrying":false,"wait":604800},"checked":814364011,"version":"1.0","buildVersion":"1"}}"#.utf8)
        let earlier = try JSONDecoder().decode([String: UpdateMemory].self, from: saved)
        let now = Date(timeIntervalSinceReferenceDate: 814364011)

        #expect(UpdateMemories(earlier).recalled(for: [app("1.0")], now: now).isEmpty)

        let current = ["com.example.foo": UpdateMemory(status: .unsupported, schedule: schedule, checked: now, describing: app("1.0"))]
        #expect(UpdateMemories(current).recalled(for: [app("1.0")], now: now) == UpdateMemories(current))

        let upToDate = try JSONDecoder().decode(
            [String: UpdateMemory].self,
            from: Data(String(decoding: saved, as: UTF8.self).replacingOccurrences(of: "unsupported", with: "upToDate").utf8)
        )
        #expect(UpdateMemories(upToDate).recalled(for: [app("1.0", feed: feed)], now: now) == UpdateMemories(upToDate))
    }

    @Test func forgetsWhatAnEarlierCheckerSaidOfAnAppNobodyIsAskedAbout() throws {
        for status in [UpdateStatus.updateAvailable(version: "2.0"), .upToDate, .failed] {
            let entry = UpdateMemory(status: status, schedule: schedule, checked: .now, describing: app("1.0"))
            let earlier = ["com.example.foo": try savedByAnEarlierChecker(entry)]
            #expect(UpdateMemories(earlier).recalled(for: [app("1.0")]).isEmpty, "\(status)")
            #expect(UpdateMemories(earlier).recalled(for: [app("1.0", feed: feed)]) == UpdateMemories(earlier), "\(status)")

            let current = ["com.example.foo": entry]
            #expect(UpdateMemories(current).recalled(for: [app("1.0")]) == UpdateMemories(current), "\(status)")
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

    @Test func keepsAnAnswerAndAScheduleForEachBuildOfAnApp() throws {
        let beta = InstalledApp(
            url: URL(filePath: "/Applications/Foo-beta.app", directoryHint: .isDirectory),
            bundleIdentifier: "com.example.foo", name: "Foo", version: "2.0", buildVersion: "9"
        )
        let found = UpdateMemory(
            status: .updateAvailable(version: "1.2", source: .appStore), schedule: schedule, checked: .now,
            describing: app("1.0"), developer: "Example"
        )
        let unchecked = UpdateMemory(
            status: .unsupported, schedule: UpdateSchedule.next(after: .unsupported), checked: .now, describing: beta
        )
        var memory = UpdateMemories()
        memory.keep(found, for: app("1.0"))
        memory.keep(unchecked, for: beta)

        let saved = try #require(memory.data.flatMap(UpdateMemories.init(data:)))
        #expect(saved == memory)
        #expect(saved.entry(for: app("1.0")) == found)
        #expect(saved.entry(for: beta) == unchecked)
        #expect(saved.developer(of: "com.example.foo") == "Example")
        #expect(saved.recalled(for: [app("1.0"), beta]) == memory)

        memory.forget(beta)
        #expect(memory.entry(for: beta) == nil && memory.entry(for: app("1.0")) == found)
    }

    @Test func readsTheOneEntryForEachAppAnEarlierPeelSaved() throws {
        let entry = UpdateMemory(status: .upToDate, schedule: schedule, checked: nil, describing: app("1.0"))
        let saved = try JSONEncoder().encode(["com.example.foo": entry])

        #expect(UpdateMemories(data: saved)?.entry(for: app("1.0")) == entry)
        #expect(UpdateMemories(data: Data("not a memory".utf8)) == nil)
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
