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
            // On the Mac's own screen, the main window filling it and Settings at its top, rather than where they
            // were restored to.
            "-ApplePersistenceIgnoreState", "YES",
            "-NSWindow Frame main", Self.saved(Self.mainWindowFrame),
            "-NSWindow Frame com_apple_SwiftUI_Settings_window", Self.saved(Self.settingsWindowFrame),
        ]
        app.launch()
        // The window can open elsewhere, even on another display, and reach its frame seconds later.
        waitUntil("The main window stands on the Mac's own screen") {
            app.windows["main"].frame == Self.onScreen(Self.mainWindowFrame)
        }

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
        waitUntilShown(app.windows["about"].links.firstMatch, named: "About")
        audit("About", appearance: appearance, of: app, window: app.windows["about"])
        app.typeKey("w", modifierFlags: .command)

        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows
            .containing(NSPredicate(format: "label == %@", "Exclusions"))
            .containing(NSPredicate(format: "label == %@", "Helper"))
            .firstMatch
        // Only its top: each pane is as tall as it needs.
        waitUntil("Settings stands at the top of the Mac's own screen") {
            settings.frame.origin == Self.onScreen(Self.settingsWindowFrame).origin
        }
        for pane in Self.settingsPanes where click(toolbarItem(pane, in: settings), named: "Settings, \(pane)") {
            audit("Settings, \(pane)", appearance: appearance, of: app, window: settings)
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

    private static func describe(_ element: any XCUIElementSnapshot) -> String {
        "\(element.elementType.rawValue) '\(text(of: element))' '\(element.identifier)' \(element.frame)"
    }

    private static func text(of element: any XCUIElementSnapshot) -> String {
        element.label.isEmpty ? element.value as? String ?? "" : element.label
    }

    /// Whether `issue` is one of what the audit reports of macOS's own drawing, or of a color Peel keeps on purpose,
    /// which no change to Peel can mend. Each was proved where it was found; anything else is recorded.
    private static func isExpected(
        _ issue: XCUIAccessibilityAuditIssue,
        _ element: (any XCUIElementSnapshot)?,
        in shown: Shown,
        sidebar: CGRect?,
        pageTitle: String
    ) -> Bool {
        // Apple's secondary label color, which Peel keeps as macOS does, reads between 3:1 and 4.5:1, and darker
        // with Increase Contrast.
        if issue.auditType == .contrast, issue.compactDescription.hasPrefix("Contrast nearly passed") { return true }
        guard let element else { return false }
        switch issue.auditType {
        case .sufficientElementDescription:
            // A container SwiftUI or AppKit makes, for a window, a column, or a list's section header, is announced
            // by what it holds. AppKit lists a Touch Bar for every app, empty on a Mac without one.
            return element.elementType == .touchBar
                || [.group, .other].contains(element.elementType) && !element.children.isEmpty
        case .parentChild:
            // SwiftUI on macOS 27 places a list section header's group 10 points above the cell that holds it.
            return element.elementType == .group && element.frame.height == 28
                && element.children.first?.elementType == .staticText
        case .contrast:
            // macOS draws the sidebar: its selection, and its labels dimmed while the window isn't key. It also
            // draws the page's title in the toolbar, with a frame that holds the toolbar's band. Home's storage is
            // one element, its words and its bar, and the bar is measured as text; the words read at least 4.5:1.
            if let sidebar, sidebar.contains(element.frame) { return true }
            if shown.emptyPageTitles.contains(key(element)) { return true }
            let words = text(of: element)
            return element.elementType == .staticText && (words == pageTitle || words.hasPrefix("Storage:"))
        default:
            return false
        }
    }

    /// What a window shows, read in one snapshot before its audit.
    private struct Shown {
        /// What tells each of its elements apart.
        var elements: Set<String> = []
        /// The titles of empty pages. ContentUnavailableView exposes its symbol and its title as one text, taller
        /// than a line, with its description centered under it, and the audit measures the symbol as the words.
        var emptyPageTitles: Set<String> = []
    }

    private static func shown(in window: XCUIElement) -> Shown {
        var shown = Shown()
        func visit(_ element: any XCUIElementSnapshot) {
            shown.elements.insert(key(element))
            for (title, description) in zip(element.children, element.children.dropFirst())
            where title.elementType == .staticText && description.elementType == .staticText
                && title.frame.height >= 64 && abs(title.frame.midX - description.frame.midX) < 1
                && description.frame.minY >= title.frame.maxY - 1 {
                shown.emptyPageTitles.insert(key(title))
            }
            element.children.forEach(visit)
        }
        if let root = try? window.snapshot() { visit(root) }
        return shown
    }

    private static func key(_ element: any XCUIElementSnapshot) -> String {
        "\(element.elementType.rawValue) \(element.label) \(element.identifier) \(element.frame)"
    }

    private static var builtInScreen: NSRect {
        let builtIn = NSScreen.screens.first { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number.map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false
        }
        return (builtIn ?? NSScreen.screens[0]).visibleFrame
    }

    private static var mainWindowFrame: NSRect { builtInScreen }

    private static var settingsWindowFrame: NSRect {
        let screen = builtInScreen
        return NSRect(x: screen.midX - 380, y: screen.maxY - 520, width: 760, height: 520)
    }

    /// `frame` written as AppKit saves a window's frame: the window's, then its screen's.
    private static func saved(_ frame: NSRect) -> String {
        let screen = builtInScreen
        let numbers = [frame.minX, frame.minY, frame.width, frame.height, screen.minX, screen.minY, screen.width,
                       screen.height]
        return numbers.map { String(Int($0)) }.joined(separator: " ") + " "
    }

    /// `frame` as XCTest reports an element's frame, measured down from the top of the screen with the menu bar.
    private static func onScreen(_ frame: NSRect) -> CGRect {
        CGRect(x: frame.minX, y: NSScreen.screens[0].frame.maxY - frame.maxY, width: frame.width, height: frame.height)
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

    /// Waits until `element` is on screen and can be clicked, so a window still appearing isn't audited half drawn.
    private func waitUntilShown(_ element: XCUIElement, named name: String) {
        let shown = expectation(for: NSPredicate(format: "exists == true AND isHittable == true"), evaluatedWith: element)
        if XCTWaiter.wait(for: [shown], timeout: 5) != .completed {
            XCTFail("\(name) wasn't shown")
        }
    }

    private func waitUntil(_ what: String, _ condition: @escaping @MainActor () -> Bool) {
        let met = expectation(for: NSPredicate { _, _ in MainActor.assumeIsolated(condition) }, evaluatedWith: nil)
        if XCTWaiter.wait(for: [met], timeout: 30) != .completed {
            XCTFail("\(what): not after 30 seconds")
        }
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

    /// Audits what is on screen. Given a `window`, only its own elements count: the audit covers every window, and
    /// the main window behind About or Settings, inactive and partly covered, is audited on its own pages.
    private func audit(_ name: String, appearance: String, of app: XCUIApplication, window: XCUIElement? = nil) {
        let shown = Self.shown(in: window ?? app.windows["main"])
        let sidebar = app.outlines.matching(NSPredicate(format: "label == %@", "Sidebar")).firstMatch
        let sidebarFrame = sidebar.exists ? sidebar.frame : nil
        let pageTitle = app.windows["main"].exists ? app.windows["main"].title : ""
        XCTContext.runActivity(named: "\(name), \(appearance)") { activity in
            let picture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            picture.name = "\(name), \(appearance)"
            picture.lifetime = .keepAlways
            activity.add(picture)
            do {
                // Each issue is recorded here, with what identifies its element, rather than by XCTest, whose picture
                // of an element scrolled out of sight fails and ends the whole run.
                try app.performAccessibilityAudit(for: Self.audits) { issue in
                    let element = try? issue.element?.snapshot()
                    if window != nil, let element, !shown.elements.contains(Self.key(element)) {
                        return true
                    }
                    if Self.isExpected(issue, element, in: shown, sidebar: sidebarFrame, pageTitle: pageTitle) {
                        return true
                    }
                    let what = element.map(Self.describe) ?? "no element"
                    XCTFail("\(name), \(appearance): \(issue.compactDescription) (\(what)): \(issue.detailedDescription)")
                    return true
                }
            } catch {
                XCTFail("The audit of \(name) couldn't run: \(error)")
            }
        }
    }
}
