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

    let file: URL
    let config: URL
    private let home: URL
    private(set) var state: State?
    private(set) var wasRefused = false

    /// Peel's own file in `folder`, and the home whose `.ssh/config` is read: the person's own unless a test gives
    /// its own.
    init(folder: URL = PeelFolder.url, home: URL = .homeDirectory) {
        file = SSHFile.url(in: folder)
        config = home.appending(path: ".ssh/config", directoryHint: .notDirectory)
        self.home = home
    }

    var lines: [String] {
        SSHFile.lines(including: file, home: home)
    }

    var hasSomethingOn: Bool {
        state?.settings.map { !$0.isEmpty } ?? false
    }

    func refresh() async {
        let accepted = if let state, !state.accepted.isEmpty { state.accepted } else { await SSHFile.accepted() }
        state = State(
            settings: SSHFile.read(file),
            isIncluded: SSHFile.isIncluded(file, from: config, home: home),
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

    /// Empties Peel's file, never one it could not read: what is in that one is not known.
    func turnAllOff() {
        guard state?.settings != nil else { return }
        write([])
    }

    private func write(_ settings: Set<SSHSetting>) {
        wasRefused = !SSHFile.write(settings, to: file)
        state?.settings = SSHFile.read(file)
    }
}
