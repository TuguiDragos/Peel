/// The tools a person chose to show or leave out of the sidebar, kept apart from the defaults: a tool never chosen
/// follows its default, which can change with the Mac (Homebrew installed or not) or with a later version of Peel.
public struct SidebarChoices: Sendable, Hashable {
    private var shown: [String: Bool]

    /// Reads `name:1` and `name:0` joined by commas. An entry that makes no sense costs that entry only, and a name
    /// this version doesn't know is kept, since a later version may.
    public init(stored: String) {
        shown = [:]
        for entry in stored.split(separator: ",") {
            let parts = entry.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, parts[1] == "1" || parts[1] == "0" else { continue }
            shown[String(parts[0])] = parts[1] == "1"
        }
    }

    /// The choices kept before there were defaults: the names of the tools left out, joined by commas.
    public init(hiddenBefore names: String) {
        shown = Dictionary(names.split(separator: ",").map { (String($0), false) }, uniquingKeysWith: { one, _ in one })
    }

    public var stored: String {
        shown.keys.sorted().map { "\($0):\(shown[$0] == true ? 1 : 0)" }.joined(separator: ",")
    }

    public func shows(_ tool: String, byDefault: Bool) -> Bool {
        shown[tool] ?? byDefault
    }

    public mutating func choose(_ tool: String, shows: Bool) {
        shown[tool] = shows
    }
}
