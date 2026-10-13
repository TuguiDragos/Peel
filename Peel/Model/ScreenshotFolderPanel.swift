import AppKit
import PeelCore

/// The open panel for the screenshot folder. It is the panel's delegate, so a folder screenshots can't be saved in is
/// refused while the panel stays open, with the reason.
final class ScreenshotFolderPanel: NSObject, NSOpenSavePanelDelegate {
    private override init() {}

    static func choose() async -> URL? {
        let delegate = ScreenshotFolderPanel()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Where should screenshots be saved?")
        panel.delegate = delegate
        let chosen = await panel.begin() == .OK ? panel.url : nil
        // The panel holds its delegate weakly: this keeps it until the panel has closed.
        extendLifetime(delegate)
        return chosen
    }

    func panel(_ sender: Any, validate url: URL) throws {
        if let problem = ScreenshotFolder.problem(with: url) { throw Refusal(problem: problem) }
    }

    private struct Refusal: LocalizedError {
        let problem: ScreenshotFolder.Problem

        var errorDescription: String? {
            switch problem {
            case .notAFolder:
                String(localized: "It isn’t there anymore.")
            case .inATrash:
                String(localized: "The Trash holds what is on its way out, so screenshots saved there would be deleted when it’s emptied.")
            case .notWritable:
                String(localized: "Screenshots can’t be saved in this folder, because you don’t have permission to write to it.")
            }
        }
    }
}
