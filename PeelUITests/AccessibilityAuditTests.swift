import XCTest

/// Runs Xcode's accessibility audit on every page of Peel, on About, on each pane of Settings, and on the menu bar
/// panel, in the light appearance and in the dark one, and keeps a picture of the screen with each result.
///
/// It moves the pointer, types, and quits a Peel that is already open, so it runs only when asked, from the
/// PeelUITests scheme, on a Mac nobody is using. macOS asks once for the test runner to get Accessibility, and for
/// an administrator's password each time Automation Mode turns on. Every audit here only reads what is on screen.
/// The action audit is left out: Apple doesn't say what it does to a control, and in Peel a switch changes a macOS
/// setting and a button moves files. For contrast under Increase Contrast, run it again with that setting on.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    private static let audits: XCUIAccessibilityAuditType = [
        .contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .parentChild,
    ]

    /// Every page, in the order of the View menu, which is the sidebar's.
    private static let pages = [
        "Home", "Tweaks", "History",
        "Applications", "Orphaned Files", "Intel Software", "Package Receipts", "Homebrew",
        "Space", "Developer", "Build Artifacts", "Installers and Backups", "Duplicates", "iCloud Drive", "File Search",
        "Background Items", "Extensions", "Plug-ins",
    ]

    private static let settingsPanes = ["General", "Exclusions", "Privacy", "Helper"]

    func testEverythingInTheLightAppearance() {
        auditEverything(appearance: "Light")
    }

    func testEverythingInTheDarkAppearance() {
        auditEverything(appearance: "Dark")
    }

    private func auditEverything(appearance: String) {
        continueAfterFailure = true
        let app = XCUIApplication()
        // In English, so menus are found by their titles, and in the appearance asked for. Arguments come before
        // the Mac's own settings, for Peel alone.
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyleSwitchesAutomatically", "NO",
            "-AppleInterfaceStyle", appearance,
        ]
        app.launch()

        for page in Self.pages {
            choose(page, inMenu: "View", of: app)
            waitForTheScan(of: page, in: app)
            audit(page, appearance: appearance, of: app)
        }

        choose("About Peel", inMenu: "Peel", of: app)
        audit("About", appearance: appearance, of: app)
        app.typeKey("w", modifierFlags: .command)

        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows
            .containing(.any, identifier: "Exclusions")
            .containing(.any, identifier: "Helper")
            .firstMatch
        for pane in Self.settingsPanes {
            settings.toolbars.descendants(matching: .any)[pane].firstMatch.click()
            audit("Settings, \(pane)", appearance: appearance, of: app)
        }
        app.typeKey("w", modifierFlags: .command)

        // The menu bar item can be turned off in Settings, and then there is no panel to look at.
        let menuBarItem = app.statusItems.firstMatch
        if menuBarItem.exists {
            menuBarItem.click()
            audit("The menu bar panel", appearance: appearance, of: app)
            menuBarItem.click()
        }

        app.terminate()
    }

    private func choose(_ item: String, inMenu menu: String, of app: XCUIApplication) {
        let title = app.menuBars.menuBarItems[menu]
        title.click()
        title.menuItems[item].click()
    }

    /// Waits for the page's scan to end. While one runs, the toolbar's Rescan turns into Stop, a moment after the
    /// scan starts.
    private func waitForTheScan(of page: String, in app: XCUIApplication) {
        let stop = app.toolbars.buttons["Stop"]
        guard stop.waitForExistence(timeout: 2) else { return }
        XCTAssertTrue(stop.waitForNonExistence(timeout: 300), "\(page) was still scanning after 5 minutes")
    }

    private func audit(_ name: String, appearance: String, of app: XCUIApplication) {
        XCTContext.runActivity(named: "\(name), \(appearance)") { activity in
            let picture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            picture.name = "\(name), \(appearance)"
            picture.lifetime = .keepAlways
            activity.add(picture)
            do {
                try app.performAccessibilityAudit(for: Self.audits)
            } catch {
                XCTFail("The audit of \(name) couldn't run: \(error)")
            }
        }
    }
}
