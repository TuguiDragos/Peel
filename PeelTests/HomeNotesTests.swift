import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct HomeNotesTests {
    @Test func theCommandLineNoteSaysWhatTheRowOffers() {
        let next = { (state: HomeModel.State, standing: CommandLineTool.Standing, place: CommandLineTool.Place) in
            HomeModel.commandLineNextStep(state: state, standing: standing, place: place).map { String(localized: $0) }
        }

        #expect(next(.on, .installed, .applications) == nil)
        #expect(next(.off, .missing, .applications)?.hasPrefix("Copy the install command") == true)
        #expect(next(.off, .otherPeel, .elsewhere)?.hasPrefix("Copy the install command") == true)
        #expect(next(.off, .missing, .temporaryCopy)?.hasPrefix("Peel is running from a copy macOS made") == true)
        #expect(next(.off, .missing, .readOnlyVolume)?.hasPrefix("Peel is running from a read-only disk") == true)
        #expect(next(.notThisAccount, .missing, .temporaryCopy)?.hasPrefix("Peel is running from a copy") == true)
        #expect(next(.notThisAccount, .missing, .applications)?.hasPrefix("Putting it on the path takes") == true)
        #expect(next(.off, .somethingElse, .applications)?.hasPrefix("Something else is at") == true)
    }

    @Test func theHelpersPointerNoteNamesWhatSystemSettingsShows() {
        #expect(HomeModel.Permission.helper.nameInSystemSettings == "Peel")
        #expect(HomeModel.Permission.appManagement.nameInSystemSettings == String(localized: "App Management"))
    }
}
