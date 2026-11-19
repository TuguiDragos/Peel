import Foundation
@testable import Peel
import PeelCore
import Testing

struct HomeBannerTests {
    @Test func theTitleSaysTheStepAndTheCircledIWhatElseThereIs() {
        #expect(MissingPermissionsNotice.setUp.title(missing: "Full Disk Access").key == "Set up %@ below")
        #expect(MissingPermissionsNotice.setUpWithHelperOfAnotherCopy.title(missing: "X").key == "Set up %@ below")
        #expect(
            MissingPermissionsNotice.setUpAndRepairTheHelper.title(missing: "X").key
                == "Set up %@ below and repair the Peel helper"
        )
        #expect(MissingPermissionsNotice.repairTheHelper.title(missing: "").key == "The Peel helper is not answering")
        #expect(
            MissingPermissionsNotice.helperOfAnotherCopy.title(missing: "").key == "The Peel helper belongs to another copy"
        )

        #expect(
            MissingPermissionsNotice.repairTheHelper.detail(otherCopy: "", reopens: false)
                == "Until you repair it below, Peel cannot move anything that needs an administrator."
        )
        #expect(MissingPermissionsNotice.helperOfAnotherCopy.detail(otherCopy: "Another copy.", reopens: false) == "Another copy.")
        #expect(
            MissingPermissionsNotice.setUpWithHelperOfAnotherCopy.detail(otherCopy: "Another copy.", reopens: true)
                == "Another copy.\n\n\(HomeModel.reopenForFullDiskAccess)"
        )
        #expect(MissingPermissionsNotice.setUpAndRepairTheHelper.detail(otherCopy: "", reopens: false) == nil)
    }

    @Test func whatWaitsInSystemSettingsIsTheTitle() {
        let helper = HomeModel.Permission.Waiting(allowsPeel: true, others: [])
        #expect(helper.title(others: "").key == "Allow Peel in Login Items & Extensions")
        #expect(helper.detail(others: "") == "Allow Peel in System Settings > General > Login Items & Extensions.")

        let others = HomeModel.Permission.Waiting(allowsPeel: false, others: [.appManagement])
        #expect(others.title(others: "App Management").key == "Check %@ in System Settings")
        #expect(others.detail(others: "App Management") == nil)

        let both = HomeModel.Permission.Waiting(allowsPeel: true, others: [.appManagement])
        #expect(both.detail(others: "App Management")?.hasSuffix("Check App Management in System Settings.") == true)
    }

    @Test func theCircledINotesSayWhatEachPermissionDoes() {
        #expect(HomeModel.Permission.helper.detail.key == "Moves the leftovers that sit in folders only an administrator can change. macOS asks you to approve it once, in Login Items & Extensions.")
        #expect(HomeModel.Permission.notifications.detail.key == "Tells you about app updates and Homebrew upgrades and, if you turn them on in Settings, about apps you move to the Trash and a disk that is almost full.")
    }
}
