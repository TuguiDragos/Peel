@testable import Peel
import PeelCore
import ServiceManagement
import Testing

@MainActor
struct HomeLoginItemTests {
    private func read(_ item: LoginItem) -> HomeModel {
        HomeModel(
            helper: HelperModel(), loginItem: item,
            readsFinderExtension: (isEnabled: { true }, runsFromAnotherCopy: { false }), readsModelName: { nil }
        )
    }

    @Test func homeShowsWhatSettingsTurnedOn() async {
        let item = LoginItem(read: { .notRegistered }) { on in
            LoginItem.Answer(status: on ? .enabled : .notRegistered)
        }
        let home = HomeModel(helper: HelperModel(), loginItem: item)
        await item.refresh()
        let before = home.state(of: .openAtLogin)

        item.set(on: true)
        while item.status != .enabled { await Task.yield() }

        #expect(before == .off)
        #expect(home.state(of: .openAtLogin) == .on)
    }

    @Test func offersToTurnOnWhatNothingElseOnHomeCan() async {
        let item = LoginItem(read: { .notRegistered }) { on in
            LoginItem.Answer(status: on ? .enabled : .notRegistered)
        }
        let home = read(item)
        #expect(home.action(for: .openAtLogin) == nil, "Home hasn't read anything yet")

        await home.refresh()
        #expect(home.action(for: .openAtLogin) == "Turn On")

        item.set(on: true)
        while item.status != .enabled { await Task.yield() }
        #expect(home.action(for: .openAtLogin) == nil)
    }

    @Test func sendsAnItemWaitingForApprovalToSystemSettings() async {
        let item = LoginItem(read: { .requiresApproval }, change: { _ in LoginItem.Answer(status: .requiresApproval) })
        let home = read(item)
        await home.refresh()

        #expect(home.action(for: .openAtLogin) == "Open System Settings")
    }

    @Test func saysWhenThePersonTurnedItOffInSystemSettings() async {
        let item = LoginItem(read: { .requiresApproval }, change: { _ in LoginItem.Answer(status: .requiresApproval) })
        let home = read(item)
        await home.refresh()

        #expect(home.status(of: .openAtLogin) == "Turned off in Login Items & Extensions")
    }

    @Test func saysWhenTurningItOnFailed() async {
        let item = LoginItem(read: { .notRegistered }) { _ in
            LoginItem.Answer(status: .notRegistered, error: "macOS said no")
        }
        let home = read(item)
        await home.refresh()

        item.set(on: true)
        while item.failure == nil { await Task.yield() }

        #expect(home.status(of: .openAtLogin) == "Couldn’t turn on")
    }
}
