import PeelCore
import SwiftUI

/// What the menu bar shows when the user clicks Peel's glyph: what Peel has moved to the Trash and since when,
/// any app updates waiting, and what each tool found the last time it looked.
struct MenuBarPanel: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppLibrary.self) private var library
    @Environment(LifetimeStats.self) private var stats
    @State private var isPointingAtUpdates = false

    static let rowPadding: CGFloat = 18
    static let iconWidth: CGFloat = 20
    static let iconSpacing: CGFloat = 13
    /// Where a row's words start, so a divider between rows begins under them.
    static let wordsInset = rowPadding + iconWidth + iconSpacing

    var body: some View {
        VStack(spacing: 0) {
            header
            hero
            Text("Since \(stats.installedOn, format: .dateTime.day().month(.wide).year())")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 30)
                .padding(.bottom, 18)
            Divider()
            rows
            MenuBarFound { open(at: $0) }
            Divider()
            footer
        }
        .frame(width: 320)
        .background(Album.sheet)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(.peelGlyph)
                .renderingMode(.template)
                .foregroundStyle(Album.orange)
            Text(verbatim: "PEEL")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .kerning(1.2)
            Spacer()
            Menu {
                SettingsLink { Text("Settings…") }
                Button("About Peel") { openWindow(id: AboutView.windowID) }
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
                .contentTransition(.numericText(value: Double(stats.bytesFreed.known)))
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
    private var rows: some View {
        // `app.dashed` is the empty slot a removed app leaves.
        row("app.dashed", stats.appsRemoved == 1 ? "App removed" : "Apps removed", stats.appsRemoved.shortCount, amount: stats.appsRemoved)
        Divider().padding(.leading, Self.wordsInset)
        row("doc.on.doc", stats.itemsRemoved == 1 ? "File removed" : "Files removed", stats.itemsRemoved.shortCount, amount: stats.itemsRemoved)
        if stats.hasABiggestCleanUp {
            Divider().padding(.leading, Self.wordsInset)
            row("internaldrive", "Biggest removal", stats.biggestCleanUp.text, amount: stats.biggestCleanUp.known)
        }
        updates
    }

    /// A check finishing while the panel is open adds a whole row to it. The row unfolds from the divider
    /// above, so the panel grows into it instead of the row landing at full height on a panel that has not
    /// made room yet. Clipped, because a half-unfolded row would otherwise draw over the footer.
    @ViewBuilder
    private var updates: some View {
        let waiting = library.menuBarUpdates
        VStack(spacing: 0) {
            if let first = waiting.first {
                Divider().padding(.leading, Self.wordsInset)
                Button {
                    // One update opens that app's page, where it is updated. Several open the list, which leads with
                    // them, rather than one app's page with its files selected for removal.
                    library.selection = waiting.count == 1 ? [first.id] : []
                    open(at: .applications)
                } label: {
                    rowContent(
                        "arrow.down.app",
                        Text("Updates waiting"),
                        waiting.count.formatted(),
                        amount: waiting.count,
                        isAccented: true,
                        leadsSomewhere: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Updates waiting"))
                .accessibilityValue(Text(verbatim: waiting.count.formatted()))
                .background(isPointingAtUpdates ? Album.slot : .clear)
                .motion(.touch, value: isPointingAtUpdates)
                .onHover { isPointingAtUpdates = $0 }
                .onDisappear { isPointingAtUpdates = false }
                .transition(.opacity)
            }
        }
        .clipped()
        // The layout itself moves here: the panel grows and shrinks as the row comes and goes, so Reduce
        // Motion stops it rather than fading it.
        .motion(.settle, .movement, value: waiting.count)
    }

    private func row(_ symbol: String, _ label: LocalizedStringResource, _ value: String, amount: some BinaryInteger) -> some View {
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
                .contentTransition(.numericText(value: Double(amount)))
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

    private func open(at tool: Tool? = nil) {
        if let tool { Navigator.shared.requestedTool = tool }
        openWindow(id: PeelApp.mainWindowID)
        NSApp.activate()
    }
}
