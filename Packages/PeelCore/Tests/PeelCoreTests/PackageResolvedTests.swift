import Foundation
import Testing

struct PackageResolvedTests {
    private struct Resolved: Decodable {
        let pins: [Pin]
    }

    private struct Pin: Decodable, Equatable {
        struct State: Decodable, Equatable {
            let revision: String
            let version: String?
        }

        let identity: String
        let location: String
        let state: State
    }

    @Test func theAppResolvesThePackagesDependenciesAsThePackageDoes() throws {
        let package = try pins(in: "Packages/PeelCore/Package.resolved")
        let app = try pins(in: "Peel.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        #expect(app == package, "Copy Packages/PeelCore/Package.resolved over the app's, so the app builds what is tested.")
    }

    private func pins(in path: String) throws -> [Pin] {
        let data = try Data(contentsOf: LineLengthTests.repository.appending(path: path))
        return try JSONDecoder().decode(Resolved.self, from: data).pins
    }
}
