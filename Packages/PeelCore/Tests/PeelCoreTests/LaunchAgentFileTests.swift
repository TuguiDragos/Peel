import Foundation
@testable import PeelCore
import Synchronization
import Testing

private func job(_ label: String = "org.example.edit", seconds: Int = 600) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<!-- kept as written -->
    \t<key>Label</key>
    \t<string>\(label)</string>
    \t<key>ProgramArguments</key>
    \t<array><string>/bin/sleep</string><string>\(seconds)</string></array>
    </dict>
    </plist>

    """
}

private func agent(
    _ plist: URL, label: String = "org.example.edit", source: BackgroundItem.Source = .userLibrary,
    kind: BackgroundItem.Kind = .agent, state: BackgroundItem.State = .running(pid: 7)
) -> BackgroundItem {
    BackgroundItem(
        label: label, kind: kind, source: source, plistURL: plist, program: "/bin/sleep", runsAtLoad: nil,
        keepsAlive: nil, ownerBundleIdentifier: nil, ownerName: nil, ownerURL: nil, isOrphan: false, state: state,
        isDisabled: false
    )
}

private final class Steps: Sendable {
    private let list = Mutex<[String]>([])

    func add(_ step: String) { list.withLock { $0.append(step) } }

    var all: [String] { list.withLock { $0 } }
}

/// A home with one agent, and a folder that stands in for the Trash.
private struct Home: ~Copyable {
    let directory: TemporaryDirectory
    let plist: URL
    let trash: URL

    init(_ text: String = job()) throws {
        let directory = try TemporaryDirectory()
        let plist = try directory.file("Library/LaunchAgents/org.example.edit.plist", contents: Data(text.utf8))
        let trash = try directory.directory("Trash")
        self.plist = plist
        self.trash = trash
        self.directory = directory
    }

    func service(steps: Steps) -> TrashService {
        let trash = trash
        return TrashService(
            environment: SearchEnvironment(homeDirectory: directory.url, rootDirectory: URL(filePath: "/"))
        ) { url in
            steps.add("move")
            let moved = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: moved)
            return moved
        }
    }

    func open(_ item: BackgroundItem) async throws -> LaunchAgentFile {
        try await LaunchAgentFile.open(item).get()
    }
}

struct LaunchAgentFileTests {
    @Test func onlyTheAgentsInTheAccountsOwnLibraryCanBeEdited() {
        let plist = URL(filePath: "/Users/x/Library/LaunchAgents/org.example.edit.plist")
        #expect(agent(plist).canBeEdited)

        #expect(!agent(URL(filePath: "/Library/LaunchAgents/org.example.edit.plist"), source: .systemLibrary).canBeEdited)
        #expect(!agent(URL(filePath: "/Library/LaunchDaemons/org.example.edit.plist"), source: .systemLibrary, kind: .daemon).canBeEdited)
        #expect(!agent(plist, source: .app).canBeEdited)
        #expect(!agent(plist, source: .otherFile).canBeEdited)
        #expect(!agent(plist, label: "com.apple.example").canBeEdited)
        let changed: [(inout BackgroundItem) -> Void] = [
            { $0.isExcluded = true }, { $0.exclusionsAreNotKnown = true }, { $0.isNamedByItsFile = true },
            { $0.isUnreadable = true }, { $0.isClosedToPeel = true }, { $0.isManagedByServiceManagement = true },
            { $0.anotherFileIsLoaded = true }, { $0.isFileGone = true }, { $0.isSystemExtension = true },
        ]
        for change in changed {
            var item = agent(plist)
            change(&item)
            #expect(!item.canBeEdited, "\(item)")
        }
    }

    @Test func opensTheFileAsWrittenAndABinaryOneAsXML() async throws {
        let home = try Home()
        let file = try await home.open(agent(home.plist))
        #expect(file.text == job())
        #expect(file.label == "org.example.edit")

        let binary = try PropertyListSerialization.data(
            fromPropertyList: ["Label": "org.example.edit", "ProgramArguments": ["/bin/sleep", "600"]],
            format: .binary, options: 0
        )
        try binary.write(to: home.plist)
        let shown = try await home.open(agent(home.plist))
        let read = try PropertyListSerialization.propertyList(from: Data(shown.text.utf8), format: nil) as? NSDictionary
        #expect(shown.text.hasPrefix("<?xml"))
        #expect(read == ["Label": "org.example.edit", "ProgramArguments": ["/bin/sleep", "600"]] as NSDictionary)
    }

    @Test func refusesALinkAnotherAccountsFileAndOneTooLarge() async throws {
        let home = try Home()
        let item = agent(home.plist)
        #expect(await LaunchAgentFile.open(item, owner: getuid() &+ 1).failure == .notYours)

        let target = try home.directory.file("dotfiles/org.example.edit.plist", contents: Data(job().utf8))
        try FileManager.default.removeItem(at: home.plist)
        try FileManager.default.createSymbolicLink(at: home.plist, withDestinationURL: target)
        #expect(await LaunchAgentFile.open(item).failure == .notAPlainFile)

        try FileManager.default.removeItem(at: home.plist)
        _ = try home.directory.file(
            "Library/LaunchAgents/org.example.edit.plist", bytes: LaunchAgentFile.maximumBytes + 1
        )
        #expect(await LaunchAgentFile.open(item).failure == .tooLarge)
        #expect(await LaunchAgentFile.open(agent(home.plist, source: .systemLibrary)).failure == .cannotBeEdited)
    }

    @Test func saysWhatMacOSAnsweredWhenTheFileCantBeRead() async throws {
        let home = try Home()
        chmod(home.plist.path(percentEncoded: false), 0)
        defer { chmod(home.plist.path(percentEncoded: false), 0o644) }

        #expect(
            await LaunchAgentFile.open(agent(home.plist)).failure
                == .unreadable(SystemError(domain: NSPOSIXErrorDomain, code: Int(EACCES)))
        )
    }

    @Test func saysWhatKeepsAnEditFromBeingSaved() async throws {
        let home = try Home()
        let file = try await home.open(agent(home.plist))
        func plist(_ body: String) -> String {
            "<?xml version=\"1.0\"?>\n<plist version=\"1.0\">\n\(body)\n</plist>\n"
        }

        #expect(file.problem(in: job(seconds: 700)) == nil)
        let broken = job().replacingOccurrences(of: "org.example.edit</string>", with: "org.example.edit</strin>")
        #expect(file.problem(in: broken) == .notAPropertyList(line: 7))
        #expect(file.problem(in: plist("<array/>")) == .notADictionary)
        #expect(file.problem(in: job("org.example.other")) == .labelChanged)
        #expect(file.problem(in: plist("<dict><key>Program</key><string>/bin/sleep</string></dict>")) == .labelChanged)
        let label = "<key>Label</key><string>org.example.edit</string>"
        #expect(file.problem(in: plist("<dict>\(label)</dict>")) == .noProgram)
        #expect(file.problem(in: plist("<dict>\(label)<key>Program</key><integer>1</integer></dict>")) == .programIsNotText)
        #expect(file.problem(in: plist("<dict>\(label)<key>Program</key><string></string></dict>")) == .programIsNotText)
        #expect(
            file.problem(in: plist("<dict>\(label)<key>ProgramArguments</key><array><integer>1</integer></array></dict>"))
                == .argumentsAreNotText
        )
        #expect(file.problem(in: plist("<dict>\(label)<key>ProgramArguments</key><array/></dict>")) == .argumentsAreNotText)
        #expect(file.problem(in: plist("<dict>\(label)<key>Program</key><string>/bin/sleep</string></dict>")) == nil)
    }

    @Test func movesTheOldFileToTheTrashWritesTheNewOneAndLoadsItAgain() async throws {
        let home = try Home()
        try home.directory.setPermissions(0o600, of: home.plist)
        let item = agent(home.plist)
        let file = try await home.open(item)
        let steps = Steps()

        let outcome = await file.save(
            job(seconds: 700), for: item, trash: home.service(steps: steps), isLoaded: { _ in true },
            stop: { _ in steps.add("stop"); return nil },
            start: { started in steps.add("start \(started.state == .notLoaded)") },
            putBack: { _ in steps.add("put back"); return nil }
        )

        guard case .saved(let moved, let reload) = outcome else { Issue.record("\(outcome)"); return }
        #expect(reload == nil)
        #expect(moved.trashed.map(\.originalURL) == [home.plist])
        #expect(moved.trashed.first?.replacedBy == TrashedItem.Identity(ofItemAt: home.plist))
        #expect(steps.all == ["move", "stop", "start true"])
        #expect(try String(contentsOf: home.plist, encoding: .utf8) == job(seconds: 700))
        #expect(try String(contentsOf: home.trash.appending(path: "org.example.edit.plist"), encoding: .utf8) == job())
        let attributes = try FileManager.default.attributesOfItem(atPath: home.plist.path(percentEncoded: false))
        let mode = attributes[.posixPermissions]
        #expect(mode as? Int == 0o600)
    }

    @Test func loadsAgainOnlyAJobLaunchdHasAsItSaves() async throws {
        // launchd is asked as the edit is saved: the page's state may be older than a load or unload made elsewhere.
        for (shown, launchdHasIt, expected) in [
            (BackgroundItem.State.notLoaded, false, ["move"]),
            (.notLoaded, true, ["move", "stop", "start"]),
            (.running(pid: 7), false, ["move"]),
            (.unknown, true, ["move", "stop", "start"]),
        ] {
            let home = try Home()
            let item = agent(home.plist, state: shown)
            let file = try await home.open(item)
            let steps = Steps()

            let outcome = await file.save(
                job(seconds: 700), for: item, trash: home.service(steps: steps),
                isLoaded: { _ in launchdHasIt },
                stop: { _ in steps.add("stop"); return nil },
                start: { _ in steps.add("start") },
                putBack: { _ in nil }
            )

            guard case .saved(_, nil) = outcome else { Issue.record("\(outcome)"); continue }
            #expect(steps.all == expected, "\(shown), launchd has it: \(launchdHasIt)")
        }
    }

    @Test func saysWhyLaunchdDidntTakeTheNewFile() async throws {
        let refused = BackgroundItemActions.Failure.launchctl("Boot-out failed: 5: Input/output error")
        let cases: [(BackgroundItemActions.Failure?, BackgroundItemActions.Failure?, LaunchAgentFile.Reload)] = [
            (refused, nil, LaunchAgentFile.Reload.notStopped(refused)),
            (nil, BackgroundItemActions.Failure.disabled, LaunchAgentFile.Reload.notStarted(.disabled)),
        ]
        for (stopping, starting, expected) in cases {
            let home = try Home()
            let item = agent(home.plist)
            let file = try await home.open(item)
            let steps = Steps()
            let outcome = await file.save(
                job(seconds: 700), for: item, trash: home.service(steps: steps), isLoaded: { _ in true },
                stop: { _ in stopping },
                start: { _ throws(BackgroundItemActions.Failure) in
                    steps.add("start")
                    if let starting { throw starting }
                },
                putBack: { _ in nil }
            )
            guard case .saved(_, let reload) = outcome else { Issue.record("\(outcome)"); continue }
            #expect(reload == expected)
            #expect(steps.all.contains("start") == (stopping == nil))
        }
    }

    @Test func movesNothingWhenTheFileChangedSinceItWasOpened() async throws {
        let home = try Home()
        let item = agent(home.plist)
        let file = try await home.open(item)
        try Data(job(seconds: 800).utf8).write(to: home.plist)
        let steps = Steps()

        let outcome = await file.save(
            job(seconds: 700), for: item, trash: home.service(steps: steps), isLoaded: { _ in true },
            stop: { _ in nil }, start: { _ in }, putBack: { _ in nil }
        )

        guard case .unchanged(.changed, let moved) = outcome else { Issue.record("\(outcome)"); return }
        #expect(moved.trashed.isEmpty && moved.failures.isEmpty)
        #expect(steps.all.isEmpty)
        #expect(try String(contentsOf: home.plist, encoding: .utf8) == job(seconds: 800))
    }

    @Test func putsTheOldFileBackWhenTheNewOneCannotBeMade() async throws {
        for putBackFails in [false, true] {
            let home = try Home()
            let item = agent(home.plist)
            let file = try await home.open(item)
            let steps = Steps()
            let denied = SystemError(domain: NSPOSIXErrorDomain, code: Int(EACCES))

            let outcome = await file.save(
                job(seconds: 700), for: item, trash: home.service(steps: steps), isLoaded: { _ in true },
                stop: { _ in nil }, start: { _ in steps.add("start") },
                putBack: { trashed in
                    steps.add("put back")
                    if putBackFails { return .missingFromTrash }
                    try? FileManager.default.moveItem(at: trashed.trashedURL, to: trashed.originalURL)
                    return nil
                },
                makeFile: { _, _, _ in .notMade(denied) }
            )

            #expect(steps.all == ["move", "put back"])
            switch outcome {
            case .unchanged(.notWritten(denied), let moved) where !putBackFails:
                #expect(moved.trashed.isEmpty)
                #expect(try String(contentsOf: home.plist, encoding: .utf8) == job())
            case .oldFileInTheTrash(.notWritten(denied), let moved) where putBackFails:
                #expect(moved.trashed.map(\.originalURL) == [home.plist])
            default:
                Issue.record("\(outcome)")
            }
        }
    }

    @Test func leavesAnIncompleteFileWhereItIsAndSaysSo() async throws {
        let home = try Home()
        let item = agent(home.plist)
        let file = try await home.open(item)
        let steps = Steps()
        let full = SystemError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))

        let outcome = await file.save(
            job(seconds: 700), for: item, trash: home.service(steps: steps), isLoaded: { _ in true },
            stop: { _ in nil }, start: { _ in steps.add("start") },
            putBack: { _ in steps.add("put back"); return nil },
            makeFile: { _, _, _ in .incomplete(full) }
        )

        guard case .oldFileInTheTrash(.incomplete(full), let moved) = outcome else { Issue.record("\(outcome)"); return }
        #expect(moved.trashed.map(\.originalURL) == [home.plist])
        #expect(steps.all == ["move"])
    }

    @Test func writesANewFileOnlyWhereNothingIsAndNeverThroughALink() throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("LaunchAgents")
        let new = folder.appending(path: "org.example.edit.plist")

        #expect(LaunchAgentFile.makeFile(at: new, holding: Data(job().utf8), mode: 0o644) == .written)
        #expect(try String(contentsOf: new, encoding: .utf8) == job())
        guard case .notMade(let error) = LaunchAgentFile.makeFile(at: new, holding: Data("x".utf8), mode: 0o644) else {
            Issue.record("wrote over a file"); return
        }
        #expect(error.code == Int(EEXIST))
        #expect(try String(contentsOf: new, encoding: .utf8) == job())

        let elsewhere = directory.url.appending(path: "elsewhere.plist")
        let link = folder.appending(path: "org.example.link.plist")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: elsewhere)
        guard case .notMade = LaunchAgentFile.makeFile(at: link, holding: Data("x".utf8), mode: 0o644) else {
            Issue.record("wrote through a link"); return
        }
        #expect(!FileManager.default.fileExists(atPath: elsewhere.path(percentEncoded: false)))
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let failure) = self { failure } else { nil }
    }
}
