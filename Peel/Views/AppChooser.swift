import AppKit
import PeelCore
import SwiftUI

/// A short list of apps to choose one from, under a search field. A menu of every app would run to the screen's edge,
/// and macOS gives a menu no shorter limit, so this list shows a few rows and scrolls past them.
struct AppChooser: View {
    private static let visibleRows = 8
    private static let rowHeight: CGFloat = 28

    @Environment(AppLibrary.self) private var library
    let apps: [InstalledApp]
    let choose: (InstalledApp) -> Void

    @State private var search = ""
    @State private var highlighted: InstalledApp.ID?

    private var shown: [InstalledApp] {
        apps.filter { AppListFilter.matches($0, text: search, developer: library.developer(of: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let shown = shown
        ScrollViewReader { proxy in
            VStack(spacing: 8) {
                SearchBox(text: $search, prompt: String(localized: "Search Applications")) { step in
                    highlighted = ListHighlight.moved(from: highlighted, by: step, among: shown.map(\.id))
                    if let highlighted { proxy.scrollTo(highlighted) }
                } onReturn: {
                    if let app = shown.first(where: { $0.id == highlighted }) { choose(app) }
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shown) { row($0) }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: CGFloat(min(max(shown.count, 1), Self.visibleRows)) * Self.rowHeight)
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

    private func row(_ app: InstalledApp) -> some View {
        Button {
            choose(app)
        } label: {
            HStack(spacing: 8) {
                AppIcon(url: app.url)
                    .frame(width: 20, height: 20)
                Text(verbatim: app.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: Self.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(highlighted == app.id ? 1 : 0), in: .rect(cornerRadius: 6))
        .onHover { if $0 { highlighted = app.id } }
        .help(Text(verbatim: app.url.abbreviatedPath))
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
