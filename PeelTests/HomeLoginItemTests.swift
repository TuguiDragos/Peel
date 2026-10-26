@testable import Peel
import PeelCore
import ServiceManagement
import Testing

@MainActor
struct HomeLoginItemTests {
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
}
