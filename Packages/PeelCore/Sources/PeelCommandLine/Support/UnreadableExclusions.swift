import Foundation
import PeelCore

/// Loads the exclusions for a scan, with a warning when they can't be read. The scan still runs, since the guard
/// moves nothing meanwhile, but it may list items the user excluded.
enum UnreadableExclusions {
    static func note(for exclusions: Exclusions, savedAt url: URL = ExclusionStore.defaultURL) -> String? {
        guard exclusions.isUnreadable else { return nil }
        return "Peel couldn't read your exclusions at \(url.path(percentEncoded: false)), so this may list what you asked it to leave alone, and nothing will be moved. Open Peel and click Start Over in Settings > Exclusions."
    }

    static func load(from store: ExclusionStore = ExclusionStore()) async -> Exclusions {
        let exclusions = await store.load()
        if let note = note(for: exclusions, savedAt: store.url) {
            Output.note(note)
        }
        return exclusions
    }
}
