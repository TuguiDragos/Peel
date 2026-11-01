/// What the exclusions say of each package, kept while nothing they go by changes: asking reads the disk while an
/// identifier is excluded, and a list asks of every outdated package each time it is drawn. What runs asks anew.
public struct ExclusionAnswers: Sendable {
    private struct Question: Sendable, Equatable {
        let exclusions: Exclusions
        let package: HomebrewPackage
        let apps: [InstalledApp]
        let installation: HomebrewInstallation?
    }

    private var kept: [HomebrewPackage.ID: (question: Question, answer: Bool?)] = [:]

    public init() {}

    public mutating func answer(
        _ exclusions: Exclusions, of package: HomebrewPackage, apps: [InstalledApp], installation: HomebrewInstallation?
    ) -> Bool? {
        let question = Question(exclusions: exclusions, package: package, apps: apps, installation: installation)
        if let known = kept[package.id], known.question == question { return known.answer }
        let answer = exclusions.excludes(package, apps: apps, installation: installation)
        kept[package.id] = (question, answer)
        return answer
    }
}
