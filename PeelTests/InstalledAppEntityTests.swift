import Foundation
@testable import Peel
import PeelCore
import Testing

struct InstalledAppEntityTests {
    private let first = InstalledApp(
        url: URL(filePath: "/Applications/Twin.app", directoryHint: .isDirectory),
        bundleIdentifier: "org.example.twin", name: "Twin"
    )
    private let second = InstalledApp(
        url: URL(filePath: "/Users/Shared/Apps/Twin.app", directoryHint: .isDirectory),
        bundleIdentifier: "org.example.twin", name: "Twin"
    )
    private let alone = InstalledApp(
        url: URL(filePath: "/Applications/Alone.app", directoryHint: .isDirectory),
        bundleIdentifier: "org.example.alone", name: "Alone"
    )

    @Test func twoCopiesOfOneAppAreToldApartAndEachOpensItself() {
        let apps = [first, second, alone]
        let entities = apps.map { InstalledAppEntity($0, among: apps) }

        #expect(Set(entities.map(\.id)).count == 3)
        #expect(entities.map(\.place) == ["/Applications", "/Users/Shared/Apps", nil])
        #expect(entities[2].id == "org.example.alone")
        for (entity, app) in zip(entities, apps) {
            #expect(InstalledAppEntity.app(withID: entity.id, among: apps)?.url == app.url)
        }
        #expect(InstalledAppEntity.app(withID: "org.example.twin", among: apps)?.url == first.url)
    }
}
