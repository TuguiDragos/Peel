@testable import PeelCore
import ServiceManagement
import Testing

@MainActor
struct LoginItemTests {
    @Test func isNotKnownUntilMacOSAnswers() async {
        let item = LoginItem(read: { .enabled }, change: { _ in LoginItem.Answer(status: .enabled) })

        let before = item.isKnown
        await item.refresh()

        #expect(!before)
        #expect(item.isKnown && item.isOn)
    }

    @Test func keepsWhatTheSwitchWasSetToUntilMacOSAnswers() async throws {
        var release: CheckedContinuation<Void, Never>?
        let item = LoginItem(read: { .notRegistered }) { on in
            await withCheckedContinuation { release = $0 }
            return LoginItem.Answer(status: on ? .enabled : .notRegistered)
        }
        await item.refresh()
        #expect(!item.isOn)

        item.set(on: true)
        #expect(item.isOn)
        while release == nil { try await Task.sleep(for: .milliseconds(1)) }
        #expect(item.isOn && item.status == .notRegistered)
        release?.resume()
        while item.status != .enabled { try await Task.sleep(for: .milliseconds(1)) }

        #expect(item.isOn && item.failure == nil)
    }

    @Test func runsOnlyTheLatestOfChangesFlippedQuickly() async throws {
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
        while release == nil { try await Task.sleep(for: .milliseconds(1)) }
        release?.resume()
        while changes.count < 2 { try await Task.sleep(for: .milliseconds(1)) }

        #expect(changes == [true, true])
        #expect(item.isOn && item.status == .enabled && item.failure == nil)
    }

    @Test func dropsAReadThatOverlappedAChange() async throws {
        var release: CheckedContinuation<Void, Never>?
        let item = LoginItem(
            read: {
                await withCheckedContinuation { release = $0 }
                return .notRegistered
            },
            change: { _ in LoginItem.Answer(status: .enabled) }
        )
        let reading = Task { await item.refresh() }
        while release == nil { try await Task.sleep(for: .milliseconds(1)) }

        item.set(on: true)
        while item.status != .enabled { try await Task.sleep(for: .milliseconds(1)) }
        release?.resume()
        await reading.value

        #expect(item.status == .enabled && item.isOn)
    }

    @Test func saysWhyAChangeFailedOnlyWhileTheItemIsNotAsAsked() async throws {
        let refused = LoginItem(read: { .notRegistered }) { _ in
            LoginItem.Answer(status: .notRegistered, error: "not allowed")
        }
        refused.set(on: true)
        while refused.failure == nil { try await Task.sleep(for: .milliseconds(1)) }
        #expect(!refused.isOn && refused.failure == "not allowed")

        let approved = LoginItem(read: { .notRegistered }) { _ in
            LoginItem.Answer(status: .requiresApproval, error: "already registered")
        }
        approved.set(on: true)
        while approved.status == nil { try await Task.sleep(for: .milliseconds(1)) }
        #expect(approved.isOn && approved.needsApproval && approved.failure == nil)
    }
}
