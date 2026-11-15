import AppKit
import Foundation
@testable import PeelCore
import Testing

@MainActor
struct AppIconStoreTests {
    private actor Maker {
        private(set) var made = 0
        private var started = 0
        private var isOpen: Bool
        private var closed: [CheckedContinuation<Void, Never>] = []
        private var watching: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

        init(open: Bool) {
            isOpen = open
        }

        func make() async {
            started += 1
            watching.removeAll { watcher in
                guard watcher.count <= started else { return false }
                watcher.continuation.resume()
                return true
            }
            if !isOpen { await withCheckedContinuation { closed.append($0) } }
            made += 1
        }

        func open() {
            isOpen = true
            closed.forEach { $0.resume() }
            closed = []
        }

        func hasStarted(_ count: Int) async {
            guard started < count else { return }
            await withCheckedContinuation { watching.append((count, $0)) }
        }
    }

    @MainActor private final class Rows {
        private(set) var told = 0
        private var watching: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

        func arrived() {
            told += 1
            watching.removeAll { watcher in
                guard watcher.count <= told else { return false }
                watcher.continuation.resume()
                return true
            }
        }

        func wereTold(_ count: Int) async {
            guard told < count else { return }
            await withCheckedContinuation { watching.append((count, $0)) }
        }
    }

    private static func store(open: Bool) -> (AppIconStore, Maker, Rows) {
        let maker = Maker(open: open)
        let rows = Rows()
        let store = AppIconStore(make: { _ in
            await maker.make()
            return NSImage(size: NSSize(width: 16, height: 16))
        }, arrived: { rows.arrived() })
        return (store, maker, rows)
    }

    private let app = URL(filePath: "/org.example/Tide.app", directoryHint: .isDirectory)

    @Test func aRowAskingAgainForAnIconItHasMakesNothing() async throws {
        let (store, maker, rows) = Self.store(open: true)

        try #require(store.icon(for: app) == nil)
        await rows.wereTold(1)
        let icon = store.icon(for: app)
        for _ in 0..<10 { #expect(store.icon(for: app) === icon) }

        #expect(icon != nil)
        #expect(await maker.made == 1)
        #expect(rows.told == 1)
    }

    @Test func aListAndARowAskingAtOnceMakeOneIcon() async {
        let (store, maker, rows) = Self.store(open: false)

        let keeping = Task { await store.keep([app]) }
        await maker.hasStarted(1)
        #expect(store.icon(for: app) == nil)
        await maker.open()
        await keeping.value

        #expect(rows.told == 1)
        #expect(store.icon(for: app) != nil)
        #expect(await maker.made == 1)
    }

    @Test func anIconMadeBeforeItsAppWasForgottenIsLeftOut() async throws {
        let (store, maker, rows) = Self.store(open: false)

        let keeping = Task { await store.keep([app]) }
        await maker.hasStarted(1)
        store.forget([app])
        await maker.open()
        await keeping.value

        try #require(store.icon(for: app) == nil, "the icon made before the app was replaced stayed")
        await rows.wereTold(1)
        #expect(store.icon(for: app) != nil)
        #expect(await maker.made == 2)
    }

    @Test func aRowWaitingForAnIconThatIsForgottenAsksAgain() async {
        let (store, maker, rows) = Self.store(open: false)

        #expect(store.icon(for: app) == nil)
        await maker.hasStarted(1)
        store.forget([app])

        #expect(rows.told == 1)
        await maker.open()
    }

    @Test func forgettingAnAppForgetsTheAppsInsideIt() async {
        let (store, _, _) = Self.store(open: true)
        let inside = app.appending(path: "Contents/Helpers/Tide Helper.app", directoryHint: .isDirectory)
        let beside = URL(filePath: "/org.example/Tide.app copy.app", directoryHint: .isDirectory)

        await store.keep([app, inside, beside])
        store.forget([app])

        #expect(store.icon(for: inside) == nil)
        #expect(store.icon(for: URL(filePath: "/org.example/Tide.app copy.app")) != nil)
    }

    @Test func theIconsOfAppsNoListKeepsStayAmongTheLastAsked() async {
        let (store, maker, rows) = Self.store(open: true)
        let apps = (0..<(AppIconStore.othersLimit + 44)).map { URL(filePath: "/org.example/App \($0).app") }

        for app in apps { #expect(store.icon(for: app) == nil) }
        await rows.wereTold(apps.count)
        let gone = apps.filter { store.icon(for: $0) == nil }
        await rows.wereTold(apps.count + gone.count)

        #expect(gone.count == 44)
        #expect(await maker.made == apps.count + 44)
    }

    @Test func forgettingEverythingMakesWhatAListKeptOnceMore() async {
        let (store, maker, rows) = Self.store(open: true)
        let asked = URL(filePath: "/org.example/Asked.app")
        await store.keep([app])
        #expect(store.icon(for: asked) == nil)
        await rows.wereTold(1)

        await store.forgetAll().value

        #expect(store.icon(for: app) != nil)
        #expect(await maker.made == 3)
        #expect(rows.told == 1)
    }
}
