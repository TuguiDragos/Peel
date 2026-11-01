import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct ExtensionTextTests {
    private func part(name: String, owner: String?, point: String?) -> AppExtension {
        AppExtension(
            identifier: "org.example.app.part", name: name, kind: .appExtension, point: point, owner: owner,
            url: URL(filePath: "/Applications/Example.app/Contents/PlugIns/Part.appex"), election: .on,
            teamIdentifier: nil, reportedState: nil
        )
    }

    @Test func aRowNamedLikeItsAppSaysWhatItPlugsInto() throws {
        let widget = part(name: "Example", owner: "Example", point: "com.apple.widgetkit-extension")
        let share = part(name: "Example", owner: "Example", point: "com.apple.share-services")

        #expect(widget.rowDetail == widget.pointName)
        #expect(widget.rowDetail != share.rowDetail, "two parts of one app read apart")
        #expect(part(name: "Example Widget", owner: "Example", point: "com.apple.widgetkit-extension").rowDetail == "Example")
        #expect(part(name: "Example", owner: nil, point: "com.apple.FinderSync").rowDetail == part(
            name: "Example", owner: nil, point: "com.apple.FinderSync"
        ).pointName)
    }

    @Test func namesThePointsAppleDocumentsAsSystemSettingsDoes() {
        let blocker = part(name: "Blocker", owner: "Example", point: "com.apple.Safari.content-blocker")
        let passwords = part(
            name: "AutoFill", owner: "Example", point: "com.apple.authentication-services-credential-provider-ui"
        )

        #expect(blocker.pointName == String(localized: "Safari"))
        #expect(passwords.pointName == String(localized: "Password AutoFill"))
        for (point, word) in [
            ("com.apple.FinderSync", String(localized: "Finder")),
            ("com.apple.fileprovider-nonui", String(localized: "File Providers")),
            ("com.apple.fileprovider-actionsui", String(localized: "File Providers")),
            ("com.apple.share-services", String(localized: "Sharing")),
            ("com.apple.photo-editing", String(localized: "Photos Editing")),
            ("com.apple.ui-services", String(localized: "Actions")),
        ] {
            #expect(part(name: "Part", owner: "Example", point: point).pointName == word)
        }
    }

    @Test func saysWhichCategorySystemSettingsListsASystemExtensionUnder() throws {
        func system(_ category: String?) -> AppExtension {
            AppExtension(
                identifier: "org.example.part", name: "Part", kind: .systemExtension, point: nil, owner: "Example",
                url: nil, election: .on, teamIdentifier: nil, reportedState: nil, category: category
            )
        }

        #expect(system("com.apple.system_extension.network_extension").categoryName == String(localized: "Network Extensions"))
        #expect(system("com.apple.system_extension.cmio").categoryName == String(localized: "Camera Extensions"))
        #expect(system("com.apple.system_extension.driver_extension").categoryName == String(localized: "Driver Extensions"))
        #expect(
            system("com.apple.system_extension.endpoint_security").categoryName
                == String(localized: "Endpoint Security Extensions")
        )
        #expect(system("org.example.unknown").categoryName == nil)
        #expect(system(nil).categoryName == nil)
        let word = try #require(system("com.apple.system_extension.cmio").categoryName)
        #expect(system("com.apple.system_extension.cmio").matches(word))
    }

    @Test func findsAPartByTheWordItsPageShows() throws {
        let widget = part(name: "Example", owner: "Example", point: "com.apple.widgetkit-extension")
        let word = try #require(widget.pointName)

        #expect(widget.matches(word))
        #expect(!part(name: "Example", owner: "Example", point: "com.apple.share-services").matches(word))
    }
}
