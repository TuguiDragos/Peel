import Foundation
import Observation
import PeelCore

@Observable
final class SSHLibrary {
    struct State: Equatable {
        var settings: Set<SSHSetting>?
        var isIncluded: Bool
        var accepted: Set<SSHSetting>
    }

    let file = SSHFile.url(in: PeelFolder.url)
    let config = URL.homeDirectory.appending(path: ".ssh/config", directoryHint: .notDirectory)
    private(set) var state: State?
    private(set) var wasRefused = false

    var lines: [String] {
        SSHFile.lines(including: file, home: .homeDirectory)
    }

    var hasSomethingOn: Bool {
        state?.settings.map { !$0.isEmpty } ?? false
    }

    func refresh() async {
        let accepted = if let state, !state.accepted.isEmpty { state.accepted } else { await SSHFile.accepted() }
        state = State(
            settings: SSHFile.read(file),
            isIncluded: SSHFile.isIncluded(file, from: config, home: .homeDirectory),
            accepted: accepted
        )
    }

    func isOffered(_ setting: SSHSetting) -> Bool {
        guard let state, state.settings != nil else { return false }
        return state.accepted.contains(setting)
    }

    func set(_ setting: SSHSetting, to isOn: Bool) {
        guard var settings = state?.settings else { return }
        if isOn {
            settings.insert(setting)
        } else {
            settings.remove(setting)
        }
        write(settings)
    }

    func turnAllOff() {
        write([])
    }

    private func write(_ settings: Set<SSHSetting>) {
        wasRefused = !SSHFile.write(settings, to: file)
        state?.settings = SSHFile.read(file)
    }
}
