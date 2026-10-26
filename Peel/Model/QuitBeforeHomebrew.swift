import AppKit
import PeelCore

/// What a Homebrew command on some casks quits first: Homebrew replaces or deletes a cask's app from under it, and
/// quits it only when the cask asks, through Apple events Peel isn't allowed to send. The apps it quits open again
/// once an upgrade is done, as Homebrew opens again what it quits itself.
struct QuitBeforeHomebrew {
    let processes: [NSRunningApplication]
    let reopening: [URL]

    @MainActor
    init(_ packages: [HomebrewPackage], library: AppLibrary) {
        let running = RunningCopies.current
        var seen: Set<pid_t> = []
        var reopening: [URL] = []
        var processes: [RunningCopies.Process] = []
        for cask in packages where cask.kind == .cask {
            let apps = library.apps.filter { library.cask(for: $0)?.id == cask.id }
            processes += RunningCopies.belonging(
                toCask: cask, apps: apps, among: running, installedApps: library.apps
            ).filter { seen.insert($0.identifier).inserted }
            reopening += apps.map(\.url).filter { url in
                running.contains { $0.bundleURL.map(PathPattern.comparablePath) == PathPattern.comparablePath(of: url) }
            }
        }
        self.processes = processes.compactMap { NSRunningApplication(processIdentifier: $0.identifier) }
        self.reopening = reopening
    }

    func reopen() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        for url in reopening where !url.isMissing {
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    }
}
