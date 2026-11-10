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

    @Test func aSystemExtensionWhoseAppIsGoneHasNothingToAllow() {
        func system(goneApp: String?) -> AppExtension {
            AppExtension(
                identifier: "org.example.part", name: "Part", kind: .systemExtension, point: nil, owner: nil,
                url: nil, election: .waitingForApproval, teamIdentifier: nil, reportedState: nil, goneApp: goneApp
            )
        }

        #expect(system(goneApp: nil).stateExplanation.key == AppExtension.Election.waitingForApproval.explanation.key)
        #expect(system(goneApp: "/Applications/Example.app").stateExplanation.key != system(goneApp: nil).stateExplanation.key)
    }

    @Test func aFinderExtensionNobodyChoseIsOff() {
        let finder = AppExtension(
            identifier: "org.example.finder", name: "Part", kind: .appExtension, point: "com.apple.FinderSync",
            owner: "Example", url: nil, election: .asItCame, teamIdentifier: nil, reportedState: nil
        )
        let other = part(name: "Part", owner: "Example", point: "com.apple.share-services")
        let chosen = AppExtension(
            identifier: "org.example.finder", name: "Part", kind: .appExtension, point: "com.apple.FinderSync",
            owner: "Example", url: nil, election: .on, teamIdentifier: nil, reportedState: nil
        )

        #expect(finder.shownElection == .off)
        #expect(chosen.shownElection == .on)
        #expect(other.shownElection == .on)
        #expect(finder.stateExplanation.key != AppExtension.Election.off.explanation.key)
    }

    @Test func aRowOfOneVersionAmongTwoKeepsItsAppBesideItsVersion() {
        func version(goneApp: String?, owner: String?) -> AppExtension {
            AppExtension(
                identifier: "org.example.part", name: "Part", kind: .systemExtension, point: nil, owner: owner,
                url: nil, election: .on, teamIdentifier: nil, reportedState: nil, goneApp: goneApp, version: "2.0/200"
            )
        }
        let installed = version(goneApp: nil, owner: "Example")
        let gone = version(goneApp: "/Applications/Example.app", owner: nil)
        let words = String(localized: "Version \("2.0 (200)")")

        #expect(installed.rowDetail(showingVersion: false) == "Example")
        #expect(installed.rowDetail(showingVersion: true) == "Example · \(words)")
        #expect(gone.rowDetail(showingVersion: true) == "\(String(localized: "\("Example"), no longer installed")) · \(words)")
    }

    @Test func aSystemExtensionOfAnAppInsideAnotherNeverPromisesFindersMove() {
        let inside = AppExtension(
            identifier: "org.example.part", name: "Part", kind: .systemExtension, point: nil, owner: "Example",
            url: nil, election: .on, teamIdentifier: nil, reportedState: nil,
            installedFor: "/Applications/Example.app/Contents/Resources/Inner.app"
        )
        for isOn27 in [false, true] {
            let resource = inside.systemExtensionNote(isOnMacOS27: isOn27, systemSettingsDeletesIt: false)
            let note = String(localized: resource)
            #expect(!note.contains("Trash in Finder"))
            #expect(note.contains("Login Items & Extensions"))
        }
    }

    @Test func aSystemExtensionsNoteSaysWhatIsLeftToDoWithIt() {
        func system(
            election: AppExtension.Election = .on, goneApp: String? = nil, replacedBy: String? = nil
        ) -> AppExtension {
            var item = AppExtension(
                identifier: "org.example.part", name: "Part", kind: .systemExtension, point: nil, owner: "Example",
                url: nil, election: election, teamIdentifier: nil, reportedState: nil, goneApp: goneApp
            )
            item.replacedBy = replacedBy
            return item
        }
        let gone = system(goneApp: "/Applications/Example.app")
        #expect(system(goneApp: "/Applications/Example.app").systemExtensionNote(
            isOnMacOS27: false, systemSettingsDeletesIt: false
        ).key == gone.leftAlone?.explanation.key)
        let goingWithANewerVersion = system(election: .beingRemoved, replacedBy: "2.20.2 (2629)")
        #expect(goingWithANewerVersion.systemExtensionNote(isOnMacOS27: false, systemSettingsDeletesIt: false).key
            == "Version %@ replaced this one, which macOS is removing. Some removals finish only when the Mac restarts.")
        let going = system(election: .beingRemoved)
        #expect(going.systemExtensionNote(isOnMacOS27: true, systemSettingsDeletesIt: true).key
            == AppExtension.Election.beingRemoved.explanation.key)
        let onItsOwn = Set([
            system().systemExtensionNote(isOnMacOS27: false, systemSettingsDeletesIt: false).key,
            system().systemExtensionNote(isOnMacOS27: true, systemSettingsDeletesIt: false).key,
            system().systemExtensionNote(isOnMacOS27: true, systemSettingsDeletesIt: true).key,
        ])
        #expect(onItsOwn.count == 3)
    }

    @Test func findsAPartByTheWordItsPageShows() throws {
        let widget = part(name: "Example", owner: "Example", point: "com.apple.widgetkit-extension")
        let word = try #require(widget.pointName)

        #expect(widget.matches(word))
        #expect(!part(name: "Example", owner: "Example", point: "com.apple.share-services").matches(word))
    }
}
