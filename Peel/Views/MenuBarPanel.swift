import PeelCore
import SwiftUI

/// What the menu bar shows when the user clicks Peel's glyph: what Peel has moved to the Trash and since when,
/// any app updates waiting, and what each tool found the last time it looked.
struct MenuBarPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(AppLibrary.self) private var library
    @Environment(LifetimeStats.self) private var stats
    @Environment(PeelUpdater.self) private var updater
    @State private var isPointingAtUpdates = false
    @State private var isPointingAtOwnUpdate = false
    @State private var room = Self.room

    static let rowPadding: CGFloat = 18
    static let iconWidth: CGFloat = 20
    static let iconSpacing: CGFloat = 13
    /// Where a row's words start, so a divider between rows begins under them.
    static let wordsInset = rowPadding + iconWidth + iconSpacing

    private static var room: CGFloat {
        MenuBarPanelRoom.height(within: NSScreen.screens.map(\.visibleFrame.height)) ?? .infinity
    }

    var body: some View {
        UpToHeight(maximum: room) {
            VStack(spacing: 0) {
                header
                // Scrolls only when the panel is taller than its room, so Open Peel stays in view.
                ViewThatFits(in: .vertical) {
                    middle
                    ScrollView { middle }
                        .scrollBounceBehavior(.basedOnSize)
                }
                Divider()
                footer
            }
            .frame(width: 320)
            .background(Album.sheet)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        ) { _ in
            room = Self.room
        }
        // macOS draws no window of a hidden app, and after a hidden launch a click on the item leaves Peel hidden.
        .onAppear { Self.showPeelIfHidden(NSApplication.shared) }
    }

    static func showPeelIfHidden(_ app: some HidingApp) {
        if app.isHidden { app.unhideWithoutActivation() }
    }

    private var middle: some View {
        VStack(spacing: 0) {
            // Home's rule: no figures until Peel has moved something, so a new install shows no zeros.
            if stats.hasCleaned {
                hero
                Text("Since \(stats.installedOn, format: .dateTime.day().month(.wide).year())")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 30)
                    .padding(.bottom, 18)
                Divider()
                totals
            } else {
                Text("Nothing moved to the Trash yet")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 34)
            }
            updates
            MenuBarFound { open(at: $0) }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            // The mark is drawn for the eye; VoiceOver hears the name, as a name rather than in capitals.
            Image(.peelGlyph)
                .renderingMode(.template)
                .foregroundStyle(Album.orange)
                .accessibilityHidden(true)
            Text(verbatim: "PEEL")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .kerning(1.2)
                .accessibilityLabel(Text(verbatim: "Peel"))
            Spacer()
            Menu {
                Button("Settings…") {
                    openSettings()
                    NSApp.activate()
                    dismiss()
                }
                Button("About Peel") {
                    openWindow(id: AboutView.windowID)
                    NSApp.activate()
                    dismiss()
                }
                Button("Check for Updates…", action: checkForUpdates)
                    .disabled(!updater.canCheckForUpdates)
                Divider()
                Button("Quit Peel") { QuitGuard.quit() }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
                    .accessibilityLabel(Text("More options for \("Peel")"))
                    .minimumTarget()
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private var hero: some View {
        VStack(spacing: 8) {
            Text(stats.bytesFreed.text)
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .monospacedDigit()
                .numberTransition(value: Double(stats.bytesFreed.known))
                .motion(value: stats.bytesFreed)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("moved to the Trash by Peel")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 34)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var totals: some View {
        // `app.dashed` is the empty slot a removed app leaves.
        row("app.dashed", stats.appsLabel, stats.appsRemoved.shortCount, amount: stats.appsRemoved)
        Divider().padding(.leading, Self.wordsInset)
        row("doc.on.doc", stats.itemsLabel, stats.itemsRemoved.shortCount, amount: stats.itemsRemoved)
        if stats.hasABiggestCleanUp {
            Divider().padding(.leading, Self.wordsInset)
            row("internaldrive", "Biggest removal", stats.biggestCleanUp.text, amount: stats.biggestCleanUp.known)
        }
    }

    /// A check finishing while the panel is open adds a whole row to it. The row unfolds from the divider
    /// above, so the panel grows into it instead of the row landing at full height on a panel that has not
    /// made room yet. Clipped, because a half-unfolded row would otherwise draw over the footer.
    @ViewBuilder
    private var updates: some View {
        let waiting = library.menuBarUpdates
        VStack(spacing: 0) {
            if let version = updater.newerVersion {
                Divider().padding(.leading, Self.wordsInset)
                updateRow(
                    "arrow.down.circle", Text("Peel \(version) is out"), value: "", amount: 0,
                    isPointing: $isPointingAtOwnUpdate, action: checkForUpdates
                )
                .disabled(!updater.canCheckForUpdates)
            }
            if let first = waiting.first {
                Divider().padding(.leading, Self.wordsInset)
                updateRow(
                    "arrow.down.app", Text("Updates waiting"), value: waiting.count.formatted(), amount: waiting.count,
                    isPointing: $isPointingAtUpdates
                ) {
                    // One update opens that app's page, where it is updated. Several open the list, which leads with
                    // them, rather than one app's page with its files selected for removal.
                    library.selection = waiting.count == 1 ? [first.id] : []
                    open(at: .applications)
                }
            }
        }
        .clipped()
        // The layout itself moves here: the panel grows and shrinks as a row comes and goes, so Reduce
        // Motion stops it rather than fading it.
        .motion(.settle, .movement, value: waiting.count)
        .motion(.settle, .movement, value: updater.newerVersion)
    }

    private func updateRow(
        _ symbol: String,
        _ label: Text,
        value: String,
        amount: Int,
        isPointing: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            rowContent(symbol, label, value, amount: amount, isAccented: true, leadsSomewhere: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: value))
        .background(isPointing.wrappedValue ? Album.slot : .clear)
        .motion(.touch, value: isPointing.wrappedValue)
        .onHover { isPointing.wrappedValue = $0 }
        .onDisappear { isPointing.wrappedValue = false }
        .transition(.opacity)
    }

    private func row(
        _ symbol: String,
        _ label: LocalizedStringResource,
        _ value: String,
        amount: some BinaryInteger
    ) -> some View {
        rowContent(symbol, Text(label), value, amount: amount, isAccented: false)
    }

    /// `amount` is the number `value` spells, so the digits roll the way it went.
    private func rowContent(
        _ symbol: String,
        _ label: Text,
        _ value: String,
        amount: some BinaryInteger,
        isAccented: Bool,
        leadsSomewhere: Bool = false
    ) -> some View {
        HStack(spacing: Self.iconSpacing) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Album.orangeInk)
                .frame(width: Self.iconWidth)
            label
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
            Spacer()
            Text(verbatim: value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .numberTransition(value: Double(amount))
                .motion(value: value)
                .foregroundStyle(isAccented ? Album.orangeInk : .primary)
            if leadsSomewhere {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, Self.rowPadding)
        .frame(height: 46)
        .contentShape(.rect)
        // One element, as a list row reads: the symbols are decoration, and the figure is the row's value.
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: value))
    }

    private var footer: some View {
        Button("Open Peel") { open() }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
    }

    /// Closes the panel too, which otherwise stays open over what it brought forward until a click elsewhere.
    private func open(at tool: Tool? = nil) {
        if let tool { Navigator.shared.requestedTool = tool }
        openWindow(id: PeelApp.mainWindowID)
        NSApp.activate()
        dismiss()
    }

    private func checkForUpdates() {
        updater.checkForUpdates()
        dismiss()
    }
}

protocol HidingApp: AnyObject {
    var isHidden: Bool { get }
    func unhideWithoutActivation()
}

extension NSApplication: HidingApp {}
