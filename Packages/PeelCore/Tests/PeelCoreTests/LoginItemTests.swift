@testable import PeelCore
import ServiceManagement
import Testing

@MainActor
struct LoginItemTests {
    @Test func keepsWhatTheSwitchWasSetToUntilMacOSAnswers() async {
        var release: CheckedContinuation<Void, Never>?
        let item = LoginItem(read: { .notRegistered }) { on in
            await withCheckedContinuation { release = $0 }
            return LoginItem.Answer(status: on ? .enabled : .notRegistered)
        }
        await item.refresh()
        #expect(!item.isOn)

        item.set(on: true)
        #expect(item.isOn)
        while release == nil { await Task.yield() }
        #expect(item.isOn && item.status == .notRegistered)
        release?.resume()
        while item.status != .enabled { await Task.yield() }

        #expect(item.isOn && item.failure == nil)
    }

    @Test func runsOnlyTheLatestOfChangesFlippedQuickly() async {
        var release: CheckedContinuation<Void, Never>?
        var changes: [Bool] = []
        let item = LoginItem(read: { .notRegistered }) { on in
            changes.append(on)
            if changes.count == 1 {
                await withCheckedContinuation { release = $0 }
                return LoginItem.Answer(status: .enabled)
            }
            return LoginItem.Answer(status: .enabled, error: "already registered")
        }

        item.set(on: true)
        item.set(on: false)
        item.set(on: true)
        #expect(item.isOn)
        while release == nil { await Task.yield() }
        release?.resume()
        while changes.count < 2 { await Task.yield() }

        #expect(changes == [true, true])
        #expect(item.isOn && item.status == .enabled && item.failure == nil)
    }

    @Test func dropsAReadThatOverlappedAChange() async {
        var release: CheckedContinuation<Void, Never>?
        let item = LoginItem(
            read: {
                await withCheckedContinuation { release = $0 }
                return .notRegistered
            },
            change: { _ in LoginItem.Answer(status: .enabled) }
        )
        let reading = Task { await item.refresh() }
        while release == nil { await Task.yield() }

        item.set(on: true)
        while item.status != .enabled { await Task.yield() }
        release?.resume()
        await reading.value

        #expect(item.status == .enabled && item.isOn)
    }

    @Test func saysWhyAChangeFailedOnlyWhileTheItemIsNotAsAsked() async {
        let refused = LoginItem(read: { .notRegistered }) { _ in
            LoginItem.Answer(status: .notRegistered, error: "not allowed")
        }
        refused.set(on: true)
        while refused.failure == nil { await Task.yield() }
        #expect(!refused.isOn && refused.failure == "not allowed")

        let approved = LoginItem(read: { .notRegistered }) { _ in
            LoginItem.Answer(status: .requiresApproval, error: "already registered")
        }
        approved.set(on: true)
        while approved.status == nil { await Task.yield() }
        #expect(approved.isOn && approved.needsApproval && approved.failure == nil)
    }
}
