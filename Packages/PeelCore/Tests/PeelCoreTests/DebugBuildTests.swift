import Foundation
import Testing

struct DebugBuildTests {
    private let configurations: [(settings: String, name: String)]

    init() throws {
        let project = try String(
            contentsOf: StringCatalogTests.repository.appending(path: "Peel.xcodeproj/project.pbxproj"), encoding: .utf8
        )
        configurations = project.matches(of: /buildSettings = \{([^}]*)\};\s*name = (Debug|Release);/).map {
            (String($0.output.1), String($0.output.2))
        }
    }

    private func groups(ofIconAt url: URL) throws -> [(name: String, layers: [String])] {
        let data = try Data(contentsOf: url.appending(path: "icon.json"))
        let document = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try #require(document["groups"] as? [[String: Any]])
        return groups.map { group in
            let layers = (group["layers"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            return (group["name"] as? String ?? "", layers)
        }
    }

    @Test func aDebugBuildWearsTheBlueprintOfPeelsIcon() throws {
        let icons = configurations.compactMap { configuration in
            configuration.settings.firstMatch(of: /ASSETCATALOG_COMPILER_APPICON_NAME = (\w+);/)
                .map { (configuration: configuration.name, icon: String($0.output.1)) }
        }
        #expect(icons.filter { $0.configuration == "Debug" }.map(\.icon) == ["PeelDebug", "PeelDebug"])
        #expect(icons.filter { $0.configuration == "Release" }.map(\.icon) == ["Peel", "Peel"])

        let repository = StringCatalogTests.repository
        let original = try groups(ofIconAt: repository.appending(path: "Logo/Peel.icon"))
        let blueprint = try groups(ofIconAt: repository.appending(path: "Logo/PeelDebug.icon"))
        #expect(blueprint.map(\.name) == ["Badge"] + original.map(\.name) + ["Blueprint Paper"])
        #expect(Array(blueprint.dropFirst().prefix(original.count)).map(\.layers) == original.map(\.layers))
    }
}
