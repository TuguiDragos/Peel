import Foundation
import PeelCore

/// Loads the exclusions for a scan, with a warning when they can't be read. The scan still runs, since the guard
/// moves nothing meanwhile: a listing may then show items the user excluded, while a search leaves out everything it
/// can't check against them (`listsEverything` false) and says so in its own note.
enum UnreadableExclusions {
    static func note(
        for exclusions: Exclusions, savedAt url: URL = ExclusionStore.defaultURL, listsEverything: Bool = true
    ) -> String? {
        guard exclusions.isUnreadable else { return nil }
        let place = Output.plain(url.path(percentEncoded: false))
        return listsEverything
            ? "Peel couldn't read your exclusions at \(place), so this may list what you asked it to leave alone, and nothing will be moved. Open Peel and click Start Over in Settings > Exclusions."
            : "Peel couldn't read your exclusions at \(place). Open Peel and click Start Over in Settings > Exclusions."
    }

    static func load(from store: ExclusionStore = ExclusionStore(), listsEverything: Bool = true) async -> Exclusions {
        let exclusions = await store.load()
        if let note = note(for: exclusions, savedAt: store.url, listsEverything: listsEverything) {
            Output.note(note)
        }
        return exclusions
    }
}
