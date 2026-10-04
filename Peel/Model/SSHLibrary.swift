import Foundation
import Observation
import PeelCore

@Observable
final class SSHLibrary {
    let file = SSHFile.url(in: PeelFolder.url)
    let config = URL.homeDirectory.appending(path: ".ssh/config", directoryHint: .notDirectory)
    private(set) var settings: Set<SSHSetting>?
    private(set) var isIncluded = false
    private(set) var accepted: Set<SSHSetting>?
    private(set) var wasRefused = false

    var lines: [String] {
        SSHFile.lines(including: file, home: .homeDirectory)
    }

    var hasSomethingOn: Bool {
        settings.map { !$0.isEmpty } ?? false
    }

    func refresh() async {
        settings = SSHFile.read(file)
        isIncluded = SSHFile.isIncluded(file, from: config, home: .homeDirectory)
        if accepted == nil {
            accepted = await SSHFile.accepted()
        }
    }

    func isOffered(_ setting: SSHSetting) -> Bool {
        settings != nil && accepted?.contains(setting) == true
    }

    func set(_ setting: SSHSetting, to isOn: Bool) {
        guard var settings else { return }
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
        self.settings = SSHFile.read(file)
    }
}
