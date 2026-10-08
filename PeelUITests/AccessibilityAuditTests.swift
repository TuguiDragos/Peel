import AppKit
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
        "Home", "Tweaks", "Terminal", "History",
        "Applications", "Orphaned Files", "Intel Software", "Package Receipts", "Homebrew",
        "Space", "Developer", "Build Artifacts", "Installers and Backups", "Duplicates", "iCloud Drive", "File Search",
        "Background Items", "Extensions", "Plug-ins",
    ]

    /// The tabs of the pages that have them, each audited on its own.
    private static let tabs = [
        "Tweaks": ["Dock", "Screenshots", "Finder", "Typing", "Windows", "Privacy"],
        "Terminal": ["Themes", "Terminal", "Shell", "Git", "SSH", "Tools"],
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
        // the Mac's own settings, for Peel alone. On a Mac set to dark, `AppleInterfaceStyle` alone leaves Peel
        // dark; `NSRequiresAquaSystemAppearance` makes the system "always apply a light appearance" (Apple,
        // Choosing a Specific Appearance for Your macOS App).
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyleSwitchesAutomatically", "NO",
            "-AppleInterfaceStyle", appearance,
            "-NSRequiresAquaSystemAppearance", appearance == "Light" ? "YES" : "NO",
            // On the Mac's own screen, filling it, rather than where the window was restored to.
            "-ApplePersistenceIgnoreState", "YES",
            "-NSWindow Frame main", Self.builtInScreenFrame,
        ]
        app.launch()

        for page in Self.pages {
            choose(page, inMenu: "View", of: app)
            waitForTheScan(of: page, in: app)
            guard let tabs = Self.tabs[page] else {
                audit(page, appearance: appearance, of: app)
                continue
            }
            for tab in tabs where click(toolbarItem(tab, in: app), named: "\(page), \(tab)") {
                audit("\(page), \(tab)", appearance: appearance, of: app)
            }
        }

        choose("About Peel", inMenu: "Peel", of: app)
        audit("About", appearance: appearance, of: app)
        app.typeKey("w", modifierFlags: .command)

        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows
            .containing(NSPredicate(format: "label == %@", "Exclusions"))
            .containing(NSPredicate(format: "label == %@", "Helper"))
            .firstMatch
        for pane in Self.settingsPanes where click(toolbarItem(pane, in: settings), named: "Settings, \(pane)") {
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

    private static func describe(_ element: XCUIElement?) -> String {
        guard let element, let found = try? element.snapshot() else { return "no element" }
        return "\(found.elementType.rawValue) '\(found.label)' '\(found.identifier)' \(found.frame)"
    }

    /// The visible frame of the Mac's built-in screen, written as a saved window frame: the window's, then the screen's.
    private static var builtInScreenFrame: String {
        let builtIn = NSScreen.screens.first { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number.map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false
        }
        let frame = (builtIn ?? NSScreen.screens[0]).visibleFrame
        let numbers = [frame.minX, frame.minY, frame.width, frame.height].map { String(Int($0)) }
        return (numbers + numbers).joined(separator: " ") + " "
    }

    /// A page's tab or a pane of Settings, found by its name, whatever kind of element the system shows it as.
    private func toolbarItem(_ name: String, in window: XCUIElement) -> XCUIElement {
        window.toolbars.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    /// Clicks `element`, or records that it isn't there, so one missing control doesn't end the audit of the rest.
    private func click(_ element: XCUIElement, named name: String) -> Bool {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("\(name) isn't there")
            return false
        }
        element.click()
        return true
    }

    private func choose(_ item: String, inMenu menu: String, of app: XCUIApplication) {
        let title = app.menuBars.menuBarItems[menu]
        title.click()
        // The menu's own items only: View > Sort and Filter holds a Homebrew and a Developer of its own.
        title.menus.firstMatch.children(matching: .menuItem)[item].click()
    }

    /// Waits for the page's scan to end. While one runs, the toolbar's Rescan turns into Stop, a moment after the
    /// scan starts.
    private func waitForTheScan(of page: String, in app: XCUIApplication) {
        let stop = app.toolbars.buttons["Stop"]
        guard stop.waitForExistence(timeout: 1) else { return }
        XCTAssertTrue(stop.waitForNonExistence(timeout: 300), "\(page) was still scanning after 5 minutes")
    }

    private func audit(_ name: String, appearance: String, of app: XCUIApplication) {
        XCTContext.runActivity(named: "\(name), \(appearance)") { activity in
            let picture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            picture.name = "\(name), \(appearance)"
            picture.lifetime = .keepAlways
            activity.add(picture)
            do {
                // Each issue is recorded here, with what identifies its element, rather than by XCTest, whose picture
                // of an element scrolled out of sight fails and ends the whole run.
                try app.performAccessibilityAudit(for: Self.audits) { issue in
                    XCTFail("\(name), \(appearance): \(issue.compactDescription) (\(Self.describe(issue.element)))")
                    return true
                }
            } catch {
                XCTFail("The audit of \(name) couldn't run: \(error)")
            }
        }
    }
}
