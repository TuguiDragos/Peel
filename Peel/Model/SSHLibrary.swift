import Foundation
import Observation
import PeelCore

@Observable
final class SSHLibrary {
    struct State: Equatable {
        var settings: Set<SSHSetting>?
        /// Why Peel's file can't be read, while `settings` is nil, when Peel knows.
        var whyUnreadable: FileProblem?
        var isIncluded: Bool
        /// What the ssh on this Mac accepts, nil while it has not answered.
        var accepted: Set<SSHSetting>?
    }

    let file: URL
    let config: URL
    private let home: URL
    private(set) var state: State?
    /// Why Peel's file couldn't be saved, until the page forgets it.
    private(set) var whyRefused: FileProblem?

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
        let accepted = if let accepted = state?.accepted { accepted } else { await SSHFile.accepted() }
        // A reading stopped because the page went away got no answer from ssh, which isn't ssh not answering.
        guard !Task.isCancelled else { return }
        let settings = SSHFile.read(file)
        state = State(
            settings: settings,
            whyUnreadable: settings == nil ? SSHFile.whyUnreadable(file) : nil,
            isIncluded: SSHFile.isIncluded(file, from: config, home: home),
            accepted: accepted
        )
    }

    func isOffered(_ setting: SSHSetting) -> Bool {
        guard let state, state.settings != nil else { return false }
        return state.accepted?.contains(setting) == true
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

    func forgetRefusal() {
        whyRefused = nil
    }

    private func write(_ settings: Set<SSHSetting>) {
        whyRefused = SSHFile.write(settings, to: file)
        let written = SSHFile.read(file)
        state?.settings = written
        state?.whyUnreadable = written == nil ? SSHFile.whyUnreadable(file) : nil
    }
}
