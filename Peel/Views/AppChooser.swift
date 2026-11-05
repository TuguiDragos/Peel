import AppKit
import PeelCore
import SwiftUI

/// What a chooser offers: an app, or a command-line tool Homebrew installed.
enum OwnerChoice: Identifiable, Hashable {
    case app(InstalledApp)
    case tool(HomebrewPackage)

    enum ID: Hashable {
        case app(InstalledApp.ID)
        case tool(String)
    }

    var id: ID {
        switch self {
        case .app(let app): .app(app.id)
        case .tool(let tool): .tool(tool.name)
        }
    }

    var name: String {
        switch self {
        case .app(let app): app.name
        case .tool(let tool): tool.name
        }
    }

    /// What Orphaned Files keeps the choice as: an app by its bundle identifier, so nil for one without, and a tool by
    /// its formula.
    var owner: OrphanOwner? {
        switch self {
        case .app(let app): app.bundleIdentifier.map(OrphanOwner.app)
        case .tool(let tool): .formula(tool.name)
        }
    }
}

/// A short list of apps, and of command-line tools when any are offered, to choose one from, under a search field. A
/// menu of every app would run to the screen's edge, and macOS gives a menu no shorter limit, so this list shows a few
/// rows and scrolls past them.
struct AppChooser: View {
    private static let visibleRows = 8
    private static let rowHeight: CGFloat = 28
    private static let headingHeight: CGFloat = 22

    @Environment(AppLibrary.self) private var library
    private let apps: [InstalledApp]
    private let tools: [HomebrewPackage]
    private let choose: (OwnerChoice) -> Void

    @State private var search = ""
    @State private var highlighted: OwnerChoice.ID?

    init(apps: [InstalledApp], choose: @escaping (InstalledApp) -> Void) {
        self.init(apps: apps, tools: []) { choice in
            if case .app(let app) = choice { choose(app) }
        }
    }

    init(apps: [InstalledApp], tools: [HomebrewPackage], choose: @escaping (OwnerChoice) -> Void) {
        self.apps = apps
        self.tools = tools
        self.choose = choose
    }

    private var shownApps: [InstalledApp] {
        apps.filter { AppListFilter.matches($0, text: search, developer: library.developer(of: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var shownTools: [HomebrewPackage] {
        tools.filter { search.isEmpty || SearchText.matches($0.name, search) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var shown: [OwnerChoice] {
        shownApps.map(OwnerChoice.app) + shownTools.map(OwnerChoice.tool)
    }

    var body: some View {
        let apps = shownApps
        let tools = shownTools
        let shown = apps.map(OwnerChoice.app) + tools.map(OwnerChoice.tool)
        // The two kinds get a heading each only while both are offered.
        let headings = self.tools.isEmpty ? 0 : (apps.isEmpty ? 0 : 1) + (tools.isEmpty ? 0 : 1)
        ScrollViewReader { proxy in
            VStack(spacing: 8) {
                SearchBox(text: $search, prompt: prompt) { step in
                    highlighted = ListHighlight.moved(from: highlighted, by: step, among: shown.map(\.id))
                    if let highlighted { proxy.scrollTo(highlighted) }
                } onReturn: {
                    if let choice = shown.first(where: { $0.id == highlighted }) { choose(choice) }
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if headings > 0, !apps.isEmpty { heading("Apps") }
                        ForEach(apps.map(OwnerChoice.app)) { row($0) }
                        if headings > 0, !tools.isEmpty { heading("Command-Line Tools") }
                        ForEach(tools.map(OwnerChoice.tool)) { row($0) }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(
                    height: CGFloat(min(max(shown.count, 1), Self.visibleRows)) * Self.rowHeight
                        + CGFloat(headings) * Self.headingHeight
                )
                .overlay {
                    if shown.isEmpty {
                        Text("No Results")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: search) {
            highlighted = search.isEmpty ? nil : self.shown.first?.id
        }
    }

    private var prompt: String {
        tools.isEmpty ? String(localized: "Search Applications") : String(localized: "Search Apps and Tools")
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .frame(height: Self.headingHeight)
    }

    private func row(_ choice: OwnerChoice) -> some View {
        Button {
            choose(choice)
        } label: {
            HStack(spacing: 8) {
                switch choice {
                case .app(let app):
                    AppIcon(url: app.url)
                        .frame(width: 20, height: 20)
                case .tool:
                    Image(systemName: "terminal")
                        .frame(width: 20, height: 20)
                }
                Text(verbatim: choice.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: Self.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(highlighted == choice.id ? 1 : 0), in: .rect(cornerRadius: 6))
        .onHover { if $0 { highlighted = choice.id } }
        .help(Text(verbatim: help(for: choice)))
    }

    /// Where an app is, or what a tool does, as Homebrew says it.
    private func help(for choice: OwnerChoice) -> String {
        switch choice {
        case .app(let app): app.url.abbreviatedPath
        case .tool(let tool): tool.summary ?? tool.name
        }
    }
}

/// macOS's own search field, holding the focus so typing goes on filtering, while its arrow keys move through the list
/// under it and its Return chooses.
private struct SearchBox: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    let onMove: (Int) -> Void
    let onReturn: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> FocusedSearchField {
        let field = FocusedSearchField()
        field.placeholderString = prompt
        field.focusRingType = .none
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: FocusedSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchBox

        init(_ parent: SearchBox) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.insertNewline(_:)): parent.onReturn()
            default: return false
            }
            return true
        }
    }
}

private final class FocusedSearchField: NSSearchField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Once the window is set up: focused before its first layout, the field draws its prompt under what is typed.
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }
}
