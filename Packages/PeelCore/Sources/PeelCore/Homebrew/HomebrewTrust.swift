/// What this Mac trusts from taps outside Homebrew's own, as `brew trust --json=v1` lists it. Since Homebrew 6.0.0
/// such a tap's packages load only once trusted, one by one or through their whole tap. Homebrew stores every
/// name in lowercase.
public struct HomebrewTrust: Sendable, Hashable, Decodable {
    public var taps: Set<String> = []
    public var formulae: Set<String> = []
    public var casks: Set<String> = []

    public init() {}

    /// Whether `package` comes from a tap outside Homebrew's own and is trusted, by itself or through its tap.
    /// An official package has no tap in its full name and never needs it.
    public func trusts(_ package: HomebrewPackage) -> Bool {
        let name = package.fullName.lowercased()
        let parts = name.split(separator: "/")
        guard parts.count == 3 else { return false }
        let items = package.kind == .cask ? casks : formulae
        return items.contains(name) || taps.contains(parts[0] + "/" + parts[1])
    }
}
