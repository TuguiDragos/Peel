import os

/// Writes named moments to the unified log as Points of Interest. Instruments shows them in a lane of their own,
/// and `/usr/bin/log show --last 5m --signpost --predicate 'subsystem == "com.tuguidragos.Peel"'` prints them.
/// They are written even when nothing is recording, so mark only a few moments worth naming.
enum Marks {
    static let moments = OSSignposter(subsystem: "com.tuguidragos.Peel", category: .pointsOfInterest)

    static func interval<T>(_ name: StaticString, _ work: () async -> T) async -> T {
        let state = moments.beginInterval(name)
        defer { moments.endInterval(name, state) }
        return await work()
    }
}
