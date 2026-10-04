import PeelCore
import SwiftUI

/// The words each tweak shows on screen.
///
/// They live in the app rather than in PeelCore beside each tweak's domain and key, because PeelCore has no
/// string catalog: a `String(localized:)` there would resolve against whichever bundle loaded it. PeelCore
/// defines what a tweak changes, and the app supplies its words, as it does for `HoldBack.explanation`.
extension Tweak {
    struct Words {
        let title: LocalizedStringResource
        let detail: LocalizedStringResource
        var caution: LocalizedStringResource?
    }

    /// The tweak's words, looked up by its id. A tweak with no entry fails an assertion in a Debug build, and
    /// shows its id in a Release build.
    var words: Words {
        guard let found = Self.words[id] else {
            assertionFailure("no words for tweak \(id)")
            // Built from the id rather than a literal, so no entry is added to the string catalog.
            let name = LocalizedStringResource(stringLiteral: id)
            return Words(title: name, detail: name)
        }
        return found
    }

    private static let words: [String: Words] = [
        "dock-autohide-delay": Words(
            title: "A hidden Dock appears at once",
            detail: "macOS waits a moment before sliding the Dock out. This removes the wait."
        ),
        "dock-autohide-time": Words(
            title: "No sliding animation for the Dock",
            detail: "The Dock appears and disappears without the slide."
        ),
        "dock-launchanim": Words(
            title: "No bouncing when an app opens",
            detail: "The icon stays still while the app starts."
        ),
        "dock-no-bouncing": Words(
            title: "Icons never bounce for attention",
            detail: "An app that needs you stops jumping up and down in the Dock.",
            caution: "You may miss an app asking for something."
        ),
        "dock-static-only": Words(
            title: "Only apps that are running",
            detail: "The Dock shows what is open and nothing else, unless a configuration profile keeps apps in it.",
            caution: "Apps you keep in the Dock are remembered, and come back when you turn this off."
        ),
        "dock-show-recents": Words(
            title: "No recent apps in the Dock",
            detail: "The extra section at the end goes away."
        ),
        "dock-minimize-to-application": Words(
            title: "Minimized windows go into the app’s icon",
            detail: "No separate thumbnail at the end of the Dock."
        ),
        "dock-mru-spaces": Words(
            title: "Spaces stay in the order you put them",
            detail: "macOS stops rearranging them by how recently you used them."
        ),
        "screenshot-thumbnail": Words(
            title: "No floating thumbnail after a screenshot",
            detail: "The screenshot is saved right away instead of floating in the corner first."
        ),
        "screenshot-location": Words(
            title: "Where screenshots are saved",
            detail: "macOS puts them on the Desktop. Choose somewhere else."
        ),
        "screenshot-shadow": Words(
            title: "No shadow around a captured window",
            detail: "A screenshot of a window shows the window alone, without its shadow."
        ),
        "screenshot-date": Words(
            title: "Screenshot names without the date",
            detail: "The name leaves out the date and time."
        ),
        "screenshot-name": Words(
            title: "What screenshots are named",
            detail: "macOS starts their names with Screenshot. Type another name to use instead."
        ),
        "screenshot-jpg": Words(
            title: "Save screenshots as JPEG",
            detail: "Smaller files than PNG, with slightly less detail."
        ),
        "finder-hidden-files": Words(
            title: "Show hidden files",
            detail: "Files whose names start with a dot appear in every window.",
            caution: "Shift-Command-Period in Finder does the same thing."
        ),
        "finder-extensions": Words(
            title: "Show every file extension",
            detail: "Finder stops hiding the part after the dot."
        ),
        "finder-path-bar": Words(
            title: "Show the path bar",
            detail: "A line at the bottom of every window says where you are."
        ),
        "finder-status-bar": Words(
            title: "Show the status bar",
            detail: "How many items are in the folder, and how much room is left."
        ),
        "finder-folders-first": Words(
            title: "Folders before files",
            detail: "Sorting by name puts folders at the top."
        ),
        "finder-extension-warning": Words(
            title: "No warning when you change an extension",
            detail: "Finder stops asking whether you’re sure when you change a file’s extension."
        ),
        "finder-posix-title": Words(
            title: "Show the full path in the title",
            detail: "A Finder window’s title says the whole path rather than the folder’s name."
        ),
        "finder-network-stores": Words(
            title: "No .DS_Store on network volumes",
            detail: "Finder stops creating .DS_Store files on network volumes, so it no longer remembers how you arranged folders there."
        ),
        "typing-press-and-hold": Words(
            title: "Holding a key repeats it",
            detail: "Instead of the accent picker, holding a letter types it again and again.",
            caution: "You lose the quick way to type accented letters."
        ),
        "typing-capitalisation": Words(
            title: "No automatic capitals",
            detail: "macOS stops capitalizing the first letter of a sentence for you."
        ),
        "typing-period": Words(
            title: "No period from a double space",
            detail: "Two spaces stay two spaces."
        ),
        "typing-quotes": Words(
            title: "Straight quotes",
            detail: "Quotation marks stay as you typed them, which code needs."
        ),
        "typing-dashes": Words(
            title: "No automatic dashes",
            detail: "Two hyphens stay two hyphens instead of becoming a long dash."
        ),
        "typing-spelling": Words(
            title: "No automatic spelling correction",
            detail: "macOS stops correcting your spelling as you type."
        ),
        "windows-scrollbars": Words(
            title: "Scroll bars are always there",
            detail: "They stay visible instead of appearing only while you scroll."
        ),
        "windows-scroll-animation": Words(
            title: "No smooth scrolling",
            detail: "A page jumps to where you sent it instead of gliding."
        ),
        "windows-resize-time": Words(
            title: "Windows resize instantly",
            detail: "When an app resizes a window itself, it happens at once.",
            caution: "It only applies when an app resizes a window. Dragging an edge is unaffected."
        ),
        "windows-drag-anywhere": Words(
            title: "Drag a window from anywhere in it",
            detail: "Hold Control and Command and drag, instead of aiming for the title bar."
        ),
        "windows-tiled-margins": Words(
            title: "No gaps between tiled windows",
            detail: "Windows snapped side by side meet exactly."
        ),
        "windows-clock-seconds": Words(
            title: "Seconds on the menu bar clock",
            detail: "The clock shows seconds instead of changing once a minute."
        ),
        "windows-save-expanded": Words(
            title: "Save dialogs open expanded",
            detail: "A Save dialog opens with your folders showing, instead of only a name and where to save it."
        ),
        "windows-print-expanded": Words(
            title: "Print dialogs open expanded",
            detail: "The Print dialog opens with its details showing.",
            caution: "Only Preview and ColorSync Utility read this setting."
        ),
        "privacy-save-locally": Words(
            title: "New documents save to this Mac",
            detail: "A Save dialog starts on this Mac instead of iCloud Drive."
        ),
        "privacy-personalised-ads": Words(
            title: "No personalized Apple ads",
            detail: "The same setting as Personalized Ads in Privacy & Security, though only the switch there tells the ad service on this Mac about the change at once."
        ),
        "privacy-crash-reporter": Words(
            title: "No crash report window",
            detail: "When an app crashes, macOS stops asking you about it."
        ),
        "terminal-fresh-windows": Words(
            title: "Terminal doesn’t reopen its windows",
            detail: "When Terminal quits, it keeps no windows to open again, even though Desktop & Dock keeps other apps’ windows."
        ),
    ]
}

#if DEBUG
extension Tweak {
    /// Checks that every tweak has words: a title, and a detail that ends with a period. The app has no test
    /// target, so Debug builds run this at launch. It reads the English keys rather than the resolved text, so
    /// it also passes in a pseudolanguage. `StringCatalogTests` checks the translations.
    static func checkWords() {
        for id in TweakCatalog.all.map(\.id) {
            guard let found = words[id] else {
                assertionFailure("no words for \(id)")
                continue
            }
            assert(!found.title.key.isEmpty, "\(id) has no title")
            assert(found.detail.key.hasSuffix("."), "\(id) doesn't explain itself")
        }
    }
}
#endif
