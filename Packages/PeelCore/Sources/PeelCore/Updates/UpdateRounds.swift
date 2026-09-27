/// The rounds of update checks under way, which apps they are asking about, and whether their answers still count.
///
/// Rounds can overlap: a round started for a bundle that changed can ask about an app another round is still
/// waiting on, so an app is being checked until every round asking about it has its answer or has ended. A round
/// started before the update source last changed asked under the old source, and none of its answers counts.
public struct UpdateRounds<ID: Hashable & Sendable>: Sendable {
    public struct Round: Hashable, Sendable {
        let number: Int
        let source: Int
    }

    private var started = 0
    private var source = 0
    private var waiting: [Round: Set<ID>] = [:]
    /// The apps at least one round is still waiting on.
    public private(set) var checking: Set<ID> = []

    public init() {}

    public mutating func begin(_ ids: some Sequence<ID>) -> Round {
        started += 1
        let round = Round(number: started, source: source)
        waiting[round] = Set(ids)
        checking.formUnion(ids)
        return round
    }

    /// Marks `id` answered in `round`, and tells whether the answer counts.
    public mutating func answered(_ id: ID, in round: Round) -> Bool {
        waiting[round]?.remove(id)
        settle([id])
        return isCurrent(round)
    }

    /// Whether `round` asked under the update source in use.
    public func isCurrent(_ round: Round) -> Bool {
        round.source == source
    }

    /// Ends `round`, answered or not.
    public mutating func end(_ round: Round) {
        settle(waiting.removeValue(forKey: round) ?? [])
    }

    public mutating func sourceChanged() {
        source += 1
    }

    private mutating func settle(_ ids: Set<ID>) {
        for id in ids where !waiting.values.contains(where: { $0.contains(id) }) {
            checking.remove(id)
        }
    }
}
