import Foundation
import Testing

@testable import PeelCore

@Suite("What Peel makes of orphaned files")
struct OrphanConfidenceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func group(
        identifier: String = "com.example.app",
        kind: SearchLocation.Kind = .applicationSupport,
        written: TimeInterval? = nil,
        size: Int64 = 1_000,
        remembered: RememberedApp? = nil
    ) -> OrphanGroup {
        let item = OrphanItem(
            url: URL(filePath: "/Users/someone/Library/Application Support/\(identifier)", directoryHint: .isDirectory),
            kind: kind,
            size: size,
            modificationDate: written.map { now.addingTimeInterval(-$0) },
            requiresPrivileges: false
        )
        return OrphanGroup(identifier: identifier, items: [item], rememberedApp: remembered)
    }

    private func left(_ name: String, team: String? = nil, daysAgo: Double = 40) -> RememberedApp {
        RememberedApp(
            bundleIdentifier: "com.example.app",
            name: name,
            teamIdentifier: team,
            lastSeen: now.addingTimeInterval(-daysAgo * 24 * 60 * 60),
            lastPath: "/Applications/\(name).app"
        )
    }

    @Test("Something running under that identifier settles it, whatever else is true")
    func runningOutranksEverything() {
        let old = group(written: 400 * 24 * 60 * 60, remembered: left("Example"))
        let judged = OrphanConfidence.judge(old, running: ["com.example.app"], now: now)
        #expect(judged.level == .unsure)
        #expect(judged.reasons == [.running])
    }

    @Test("A folder written this week belongs to something that still runs, even if no app claims it")
    func recentWritingOutranksAGoneApp() {
        let fresh = group(written: 2 * 24 * 60 * 60, remembered: left("Example"))
        let judged = OrphanConfidence.judge(fresh, now: now)
        #expect(judged.level == .unsure)
        if case .writtenRecently = judged.reasons.first {} else {
            Issue.record("expected the recent writing to be the reason, got \(judged.reasons)")
        }
    }

    @Test("A write that was the uninstall itself is not read as something still running")
    func theWriteWasTheRemoval() {
        // Peel last saw the app four days ago; the folder was written four days ago too, when its files
        // were taken out. That is the removal, not an app that is still working.
        let removed = left("Example", daysAgo: 4)
        let judged = OrphanConfidence.judge(group(written: 4 * 24 * 60 * 60, remembered: removed), now: now)
        #expect(judged.level == .certain)
        #expect(judged.reasons.contains { if case .appLeft = $0 { true } else { false } })
    }

    @Test("A write after the app was last seen is still something running")
    func writingAfterwardsStillCounts() {
        let removed = left("Example", daysAgo: 6)
        let judged = OrphanConfidence.judge(group(written: 1 * 24 * 60 * 60, remembered: removed), now: now)
        #expect(judged.level == .unsure)
    }

    @Test("What an app left is doubted while its maker still has another app installed")
    func aMakerStillHere() {
        let shared = group(written: 300 * 24 * 60 * 60, remembered: left("Example", team: "S8EX82NJP6"))
        let judged = OrphanConfidence.judge(shared, installedTeams: ["S8EX82NJP6"], now: now)
        #expect(judged.level == .unsure)
        #expect(judged.reasons == [.sameMakerStillInstalled])
    }

    @Test("Having watched the app go does not settle it either: a maker's other app may only ever read what they share")
    func aMakerStillHereOutranksHavingWatchedTheAppGo() {
        let removed = left("Example", team: "S8EX82NJP6", daysAgo: 40)
        let judged = OrphanConfidence.judge(
            group(written: 40 * 24 * 60 * 60, remembered: removed),
            installedTeams: ["S8EX82NJP6"],
            now: now
        )
        #expect(judged.level == .unsure)
        #expect(judged.reasons == [.sameMakerStillInstalled])
    }

    @Test("What is running is matched the way an app is: a helper runs under its app's identifier and a longer one")
    func aRunningHelperOrItsAppBothCount() {
        let old = group(identifier: "com.example.app", written: 400 * 24 * 60 * 60)
        #expect(OrphanConfidence.judge(old, running: ["com.example.app.helper"], now: now).reasons == [.running])
        #expect(OrphanConfidence.judge(old, running: ["COM.EXAMPLE.APP"], now: now).reasons == [.running])
        let helper = group(identifier: "com.example.app.helper", written: 400 * 24 * 60 * 60)
        #expect(OrphanConfidence.judge(helper, running: ["com.example.app"], now: now).reasons == [.running])
        // Two components name a maker, not an app, and `com.example.apple` is not a helper of `com.example.app`.
        let other = group(identifier: "com.example.other", written: 400 * 24 * 60 * 60)
        #expect(OrphanConfidence.judge(other, running: ["com.example"], now: now).level == .certain)
        #expect(OrphanConfidence.judge(old, running: ["com.example.apple"], now: now).level == .certain)
    }

    @Test("A Safari web app is its own app: Safari running, or another web app, says nothing about it")
    func safariRunningSaysNothingOfAWebApp() {
        let identifier = "com.apple.Safari.WebApp.0E4F6A2C-1B3D-4E5F-8A9B-0C1D2E3F4A5B"
        let webApp = group(identifier: identifier, written: 400 * 24 * 60 * 60)
        #expect(OrphanConfidence.judge(webApp, running: ["com.apple.Safari"], now: now).level == .certain)
        #expect(OrphanConfidence.judge(webApp, running: ["com.apple.Safari.WebApp"], now: now).level == .certain)
        #expect(OrphanConfidence.judge(webApp, running: [identifier], now: now).reasons == [.running])
    }

    @Test("An app Peel watched leave is the strongest thing it can say")
    func peelWatchedItGo() {
        let judged = OrphanConfidence.judge(group(written: 60 * 24 * 60 * 60, remembered: left("Numi")), now: now)
        #expect(judged.level == .certain)
        #expect(judged.reasons.contains { if case .appLeft(let name, _) = $0 { name == "Numi" } else { false } })
    }

    @Test("Something that wrote here weeks after the app was gone may still use the files, and the write is the reason")
    func aWriteWeeksAfterTheAppLeft() {
        let judged = OrphanConfidence.judge(
            group(written: 20 * 24 * 60 * 60, remembered: left("Numi", daysAgo: 60)),
            now: now
        )
        #expect(judged.level == .unsure)
        #expect(judged.reasons == [.writtenAfterItLeft(name: "Numi", written: now.addingTimeInterval(-20 * 24 * 60 * 60))])
    }

    @Test("Months of nothing touching it settle it even when something wrote after the app was gone")
    func aWriteAfterTheAppLeftLongAgo() throws {
        let judged = OrphanConfidence.judge(
            group(written: 250 * 24 * 60 * 60, remembered: left("Numi", daysAgo: 400)),
            now: now
        )
        #expect(judged.level == .certain)
        #expect(judged.reasons.count == 1)
        guard case .untouched(let months) = try #require(judged.reasons.first) else {
            Issue.record("expected the months without a write to be the reason, got \(judged.reasons)")
            return
        }
        #expect(months >= OrphanConfidence.longUntouched)
    }

    @Test("Files that were not read in time say nothing about when they were written, so seeing the app go is not enough")
    func aGoneAppWhoseFilesWereNotRead() {
        let item = OrphanItem(
            url: URL(filePath: "/Users/someone/Library/Application Support/com.example.app", directoryHint: .isDirectory),
            kind: .applicationSupport,
            size: nil,
            modificationDate: now.addingTimeInterval(-400 * 24 * 60 * 60),
            requiresPrivileges: false
        )
        let numi = left("Numi")
        let judged = OrphanConfidence.judge(OrphanGroup(identifier: "com.example.app", items: [item], rememberedApp: numi), now: now)
        #expect(judged.level == .likely)
        #expect(judged.reasons == [.appLeft(name: "Numi", lastSeen: numi.lastSeen)])
    }

    @Test("Months of nothing touching it is enough on its own")
    func longUntouched() {
        let judged = OrphanConfidence.judge(group(written: 400 * 24 * 60 * 60), now: now)
        #expect(judged.level == .certain)
        #expect(
            judged.reasons.contains {
                if case .untouched(let months) = $0 { months >= OrphanConfidence.longUntouched } else { false }
            }
        )
    }

    @Test("A plug-in's date does not move when it is used, so its age says nothing")
    func aPlugInsAgeSaysNothing() {
        let judged = OrphanConfidence.judge(group(kind: .plugIns, written: 400 * 24 * 60 * 60), now: now)
        #expect(judged.level == .likely)
        #expect(judged.reasons == [.nothingClaimsIt])
    }

    @Test("A folder that did not answer was not read, so nothing is said about when it was last written")
    func aFolderThatDidNotAnswerSaysNothingAboutItsDates() {
        let item = OrphanItem(
            url: URL(filePath: "/Users/someone/Library/Application Support/com.example.app", directoryHint: .isDirectory),
            kind: .applicationSupport,
            size: nil,
            modificationDate: now.addingTimeInterval(-400 * 24 * 60 * 60),
            requiresPrivileges: false
        )
        let untouched = OrphanConfidence.judge(OrphanGroup(identifier: "com.example.app", items: [item]), now: now)
        #expect(untouched.level == .likely)
        #expect(untouched.reasons == [.nothingClaimsIt])

        // Nor is its own date read as the removal: what is inside may have been written since.
        let removed = left("Example", daysAgo: 4)
        let recent = OrphanItem(
            url: item.url,
            kind: .applicationSupport,
            size: nil,
            modificationDate: now.addingTimeInterval(-4 * 24 * 60 * 60),
            requiresPrivileges: false
        )
        let judged = OrphanConfidence.judge(
            OrphanGroup(identifier: "com.example.app", items: [recent], rememberedApp: removed),
            now: now
        )
        #expect(judged.level == .unsure)
    }

    @Test("With nothing else to go on, Peel says only that nothing claims it")
    func nothingElseToSay() {
        let judged = OrphanConfidence.judge(group(written: 30 * 24 * 60 * 60), now: now)
        #expect(judged.level == .likely)
        #expect(judged.reasons == [.nothingClaimsIt])
    }

    @Test("A date in the future is not read as writing that has just happened")
    func aClockThatRanAhead() {
        let judged = OrphanConfidence.judge(group(written: -10 * 24 * 60 * 60), now: now)
        #expect(judged.level == .likely)
        // Nor as the removal of an app Peel saw go: that write would have to come before it.
        let afterTheApp = OrphanConfidence.judge(group(written: -10 * 24 * 60 * 60, remembered: left("Numi")), now: now)
        #expect(afterTheApp.level == .likely)
    }

    @Test("What Peel is sure about is listed first, and the largest of those first again")
    func theOrder() {
        let found: [(identifier: String, item: OrphanItem)] = [
            ("com.example.unsure", group(identifier: "com.example.unsure", written: 0, size: 900_000).items[0]),
            ("com.example.small", group(identifier: "com.example.small", written: 400 * 24 * 60 * 60, size: 10).items[0]),
            ("com.example.large", group(identifier: "com.example.large", written: 400 * 24 * 60 * 60, size: 500).items[0]),
        ]
        let groups = OrphanScanner.group(found, now: now)
        #expect(groups.map(\.identifier) == ["com.example.large", "com.example.small", "com.example.unsure"])
        #expect(groups.first?.confidence.level == .certain)
        #expect(groups.last?.confidence.level == .unsure)
    }
}
