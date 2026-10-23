import Observation
import PeelCore

/// The copies of settings that app resets kept, newest first. Read when first asked for, so Settings draws them in
/// its first frame, then again by whatever makes or removes a copy, and by Settings when it appears or Peel comes
/// forward, since a copy can also be removed in Finder.
@Observable
final class SavedSettings {
    static let shared = SavedSettings()

    /// Nil while the folder that keeps them can't be read.
    private(set) var copies = PreferenceBackup.copies()

    private init() {}

    func reload() {
        copies = PreferenceBackup.copies()
    }
}
