import Foundation

extension HomebrewPackage {
    /// What `brew upgrade` of this formula upgrades with it, as Homebrew does (`upgrade.rb`): the outdated formulae it
    /// depends on, and the outdated installed formulae that depend on it, directly or through others, unless pinned.
    public func upgradedWith(among installed: [HomebrewPackage]) -> [HomebrewPackage] {
        guard kind == .formula else { return [] }
        let formulae = Dictionary(installed.filter { $0.kind == .formula }.map { ($0.name, $0) }) { first, _ in first }
        var dependencies: Set<String> = []
        var next = self.dependencies
        while let name = next.popLast() {
            guard name != self.name, dependencies.insert(name).inserted else { continue }
            next += formulae[name]?.dependencies ?? []
        }
        var dependents: Set<String> = []
        var reached: Set<String> = [name]
        var grew = true
        while grew {
            grew = false
            for formula in formulae.values
            where !reached.contains(formula.name) && formula.dependencies.contains(where: reached.contains) {
                reached.insert(formula.name)
                dependents.insert(formula.name)
                grew = true
            }
        }
        return formulae.values
            .filter { formula in
                formula.isOutdated
                    && (dependencies.contains(formula.name) || dependents.contains(formula.name) && !formula.isPinned)
            }
            .sorted { $0.name < $1.name }
    }
}
