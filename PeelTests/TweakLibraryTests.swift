import Foundation
@testable import Peel
import PeelCore
import Testing

/// Tweak settings as a test keeps them in memory, never the Mac's own.
private final class FakeTweakStore: TweakStoring {
    var values: [String: Any] = [:]
    var refuses: Set<Tweak.ID> = []

    func beginReading() {}

    func state(of tweak: Tweak) -> TweakState {
        let value = values[tweak.id]
        switch tweak.kind {
        case .aSwitch(let wanted), .aSwitchForThisAppAlone(let wanted):
            let isOn = switch wanted {
            case .boolean(let flag): value as? Bool == flag
            case .number(let number): value as? Double == number
            case .text(let text): value as? String == text
            }
            return TweakState(isOn: isOn, isManaged: false, text: nil)
        case .folder, .name:
            let text = value as? String
            return TweakState(isOn: text?.isEmpty == false, isManaged: false, text: text)
        }
    }

    func storedValue(of tweak: Tweak) -> Any? { values[tweak.id] }

    func turnOn(_ tweak: Tweak, text: String?) -> Bool {
        guard !refuses.contains(tweak.id) else { return false }
        switch tweak.kind {
        case .aSwitch(let wanted), .aSwitchForThisAppAlone(let wanted):
            values[tweak.id] = switch wanted {
            case .boolean(let flag): flag
            case .number(let number): number
            case .text(let text): text
            }
        case .folder, .name:
            values[tweak.id] = text
        }
        return true
    }

    func restore(_ value: Any?, for tweak: Tweak) -> Bool {
        guard !refuses.contains(tweak.id) else { return false }
        values[tweak.id] = value
        return true
    }
}

struct TweakLibraryTests {
    /// Tweaks that restart nothing, so a test never ends a process of the Mac it runs on.
    private static let quiet = TweakCatalog.all.filter { $0.restart == .none && $0.group == .screenshots }

    /// The restarts a library asked for, in order, instead of a `killall` of this Mac's own processes.
    private final class Restarts {
        var asked: [Tweak.Restart] = []
    }

    private func makeLibrary(
        store: FakeTweakStore, restarts: Restarts = Restarts()
    ) throws -> (TweakLibrary, MadeUpDefaults) {
        let made = try MadeUpDefaults()
        let library = TweakLibrary(store: store, defaults: made.defaults) { needed in
            await MainActor.run { restarts.asked.append(needed) }
        }
        return (library, made)
    }

    @Test func turnAllOffPutsBackOnlyWhatPeelChangedAndRestartsEachProcessOnce() async throws {
        let store = FakeTweakStore()
        let restarts = Restarts()
        let (library, made) = try makeLibrary(store: store, restarts: restarts)
        defer { made.forget() }
        let docks = TweakCatalog.all.filter { $0.restart == .dock }
        let (byPeel, alsoByPeel, byHand) = (docks[0], docks[1], docks[2])
        #expect(store.turnOn(byHand, text: nil))
        await library.set(byPeel, on: true).value
        await library.set(alsoByPeel, on: true).value
        #expect(library.peelsChanges == [byPeel.id, alsoByPeel.id])
        #expect(restarts.asked == [.dock, .dock])

        await library.turnAllOff()

        #expect(store.values[byPeel.id] == nil && store.values[alsoByPeel.id] == nil)
        #expect(store.state(of: byHand).isOn, "a setting the person made is theirs")
        #expect(library.peelsChanges.isEmpty)
        #expect(restarts.asked == [.dock, .dock, .dock])
    }

    @Test func putBackHandsTheScreenshotFolderToMacOSWhenTheFolderFromBeforeIsGone() async throws {
        let store = FakeTweakStore()
        let (library, made) = try makeLibrary(store: store)
        defer { made.forget() }
        let folder = try #require(TweakCatalog.all.first { $0.kind == .folder })
        let gone = FileManager.default.temporaryDirectory.appending(path: "TweakLibraryTests-\(UUID().uuidString)")
        store.values[folder.id] = gone.path(percentEncoded: false)
        await library.turnOn(folder, text: "/Users/Shared")

        await library.reset(folder)

        #expect(store.values[folder.id] == nil)
        #expect(library.foldersLeftToMacOS == [folder.id])
        #expect(!library.isChangedByPeel(folder))
        await library.turnOn(folder, text: "/Users/Shared")
        #expect(library.foldersLeftToMacOS.isEmpty)
    }

    @Test func putBackReturnsAScreenshotFolderThatIsStillThere() async throws {
        let store = FakeTweakStore()
        let (library, made) = try makeLibrary(store: store)
        defer { made.forget() }
        let folder = try #require(TweakCatalog.all.first { $0.kind == .folder })
        let before = FileManager.default.temporaryDirectory.appending(
            path: "TweakLibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: before, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: before) }
        store.values[folder.id] = ScreenshotFolder.setting(for: before)
        await library.turnOn(folder, text: "/Users/Shared")

        await library.reset(folder)

        #expect(store.values[folder.id] as? String == ScreenshotFolder.setting(for: before))
        #expect(library.foldersLeftToMacOS.isEmpty)
    }

    @Test func twoRefusedSwitchesBothSaySo() async throws {
        let store = FakeTweakStore()
        let (library, made) = try makeLibrary(store: store)
        defer { made.forget() }
        let first = try #require(Self.quiet.first { $0.kind != .folder && $0.kind != .name })
        let second = try #require(Self.quiet.last { $0.kind != .folder && $0.kind != .name })
        store.refuses = [first.id, second.id]

        await library.set(first, on: true).value
        await library.set(second, on: true).value

        #expect(library.refused == [first.id, second.id])
    }

    @Test func aRefusalStaysWhileAnotherSwitchSucceeds() async throws {
        let store = FakeTweakStore()
        let (library, made) = try makeLibrary(store: store)
        defer { made.forget() }
        let first = try #require(Self.quiet.first { $0.kind != .folder && $0.kind != .name })
        let second = try #require(Self.quiet.last { $0.kind != .folder && $0.kind != .name })
        store.refuses = [first.id]

        await library.set(first, on: true).value
        await library.set(second, on: true).value
        #expect(library.refused == [first.id])

        store.refuses = []
        await library.set(first, on: true).value
        #expect(library.refused.isEmpty)
    }
}
