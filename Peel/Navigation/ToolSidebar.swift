import AppKit
import PeelCore
import SwiftUI

/// Where the sidebar can take the user. Settings is a row chosen like the tools and opens as a page in this
/// window, because a row that opened another window would behave unlike the rows around it. About opens from
/// Peel's face at the top of the column.
enum SidebarDestination: Hashable {
    case tool(Tool)
    case settings
    case about
}

struct ToolSidebar: View {
    @Environment(HomeModel.self) private var home
    @Environment(AppLibrary.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("sidebar.apps.expanded") private var isAppsExpanded = true
    @AppStorage("sidebar.storage.expanded") private var isStorageExpanded = true
    @AppStorage("sidebar.system.expanded") private var isSystemExpanded = true
    /// Tools the user turned off in Settings. They leave the sidebar only: the View menu, Shortcuts, and links
    /// still open them, as Finder's Go menu opens a place its sidebar hides.
    @AppStorage(SettingsKey.sidebarTools) private var sidebarTools = ""
    @Environment(HomebrewLibrary.self) private var homebrew
    @Binding var tool: Tool
    @Binding var page: SidebarDestination?
    /// The column's width, set by the widest label, because in some languages the longer tool names need more
    /// than 220 points.
    @Binding var width: CGFloat

    static let minimumWidth: CGFloat = 220
    /// Beyond this width a label is cut short, so the sidebar cannot take too much room from the page.
    private static let maximumWidth: CGFloat = 320
    /// The room a row keeps around its label at the default sidebar size: in a column 220 points wide, a label
    /// runs from 29 to 212.
    private static let rowInsets: CGFloat = 37

    /// The widest label, as the ruler lays it out.
    @State private var widestLabel: CGFloat = 0
    /// The width a scroll bar takes from every row when scroll bars sit beside the content (`.legacy`), or 0 when
    /// they overlay it. Without it, the longest label is cut when the window is too short for the whole list.
    @State private var scrollerRoom = Self.currentScrollerRoom

    private static var currentScrollerRoom: CGFloat {
        NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            : 0
    }

    /// One selection for the whole sidebar, mapped onto the two bindings behind it, `tool` and `page`. It is built
    /// here rather than passed in, because a `Binding` created in the parent's body makes this view's body run
    /// again every time the parent's body runs.
    private var selection: Binding<SidebarDestination?> {
        Binding(
            get: { page ?? .tool(tool) },
            set: { chosen in
                switch chosen {
                case .tool(let newTool): tool = newTool; page = nil
                case .settings, .about: page = chosen
                case nil: break
                }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(shown(Tool.Group.home.tools), content: row)
                Label { Text("Settings") } icon: { icon("gearshape") }
                    .tag(SidebarDestination.settings)
            }

            group(.apps, isExpanded: $isAppsExpanded)
            group(.storage, isExpanded: $isStorageExpanded)
            group(.system, isExpanded: $isSystemExpanded)
        }
        // A bar on every macOS, unlike a page's (`edgeBar`): the face is glass on the sidebar's glass, and glass
        // cannot sample other glass, so the bar's own edge effect is what blurs the rows passing under it.
        .safeAreaBar(edge: .top, spacing: 0) { mascot }
        .takesFocusWhenNothingHasIt()
        .onReceive(
            NotificationCenter.default.publisher(for: NSScroller.preferredScrollerStyleDidChangeNotification)
        ) { _ in
            scrollerRoom = Self.currentScrollerRoom
            fitWidth()
        }
        // Opens the group of a tool chosen from outside the sidebar, such as from a link, a Shortcut, or the View
        // menu, so that the selected row can be seen.
        .onChange(of: selection.wrappedValue) { _, chosen in
            guard case .tool(let tool) = chosen else { return }
            switch tool.group {
            case .apps: isAppsExpanded = true
            case .storage: isStorageExpanded = true
            case .system: isSystemExpanded = true
            case .home: break
            }
        }
    }

    /// Peel's face, name, and version at the top of the column, on glass over the list. Clicking it opens About.
    /// Before macOS 27 it rises into the lower half of the title bar, which is otherwise empty above the sidebar.
    private var mascot: some View {
        Button {
            page = .about
        } label: {
            HStack(spacing: Head.spacing) {
                PeelFace(size: Head.face)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Peel")
                        .font(.callout.weight(.semibold))
                    versionLine
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                if library.newerPeel != nil {
                    Image(systemName: "arrow.down.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: Head.icon, height: Head.icon)
                        .foregroundStyle(.tint)
                        .help(versionLine)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .motion(value: library.newerPeel)
            .padding(.leading, Head.leading)
            .padding(.trailing, Head.trailing)
            .padding(.vertical, Head.vertical)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, Head.margin)
        .padding(.top, Head.rise)
        .padding(.bottom, 8)
        .accessibilityLabel(Text(AboutView.title))
        .accessibilityValue(library.newerPeel.map { Text("Version \($0.version) is out.") } ?? Text(verbatim: AppVersion.display))
    }

    private var versionLine: Text {
        library.newerPeel.map { Text("\($0.version) is out") } ?? Text(verbatim: AppVersion.display)
    }

    /// The head's measures, which the ruler also reads to leave its second line room beside the face and the icon.
    private enum Head {
        static let face: CGFloat = 30
        static let spacing: CGFloat = 9
        static let icon: CGFloat = 18
        static let leading: CGFloat = 7
        static let vertical: CGFloat = 6
        /// Half the capsule's height less half the icon, so the icon is centered in the capsule's rounded end.
        static let trailing = (face + 2 * vertical - icon) / 2
        static let margin: CGFloat = 10
        /// How far the head rises into the title bar. On macOS 27 the sidebar button there sits on a glass circle
        /// that reaches the title bar's lower edge, so the head stays below it.
        static var rise: CGFloat {
            if #available(macOS 27, *) { 0 } else { -8 }
        }
    }

    /// A group whose rows are added and removed here rather than by a collapsible `Section`, because SwiftUI
    /// restores a section's expanded state on its own and would decide whether a group starts open.
    @ViewBuilder
    private func group(_ group: Tool.Group, isExpanded: Binding<Bool>) -> some View {
        let tools = shown(group.tools)
        if !tools.isEmpty {
            Section {
                heading(group, isExpanded: isExpanded)
                if isExpanded.wrappedValue {
                    ForEach(tools, content: row)
                }
            }
        }
    }

    private func shown(_ tools: [Tool]) -> [Tool] {
        let hidden = Tool.hidden(by: SidebarChoices(stored: sidebarTools), homebrewIsInstalled: homebrew.isInstalled)
        return tools.filter { !hidden.contains($0) }
    }

    private func heading(_ group: Tool.Group, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : Motion.step.animation) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                if let title = group.title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 2)
            .minimumTarget()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isExpanded.wrappedValue ? Text("Expanded") : Text("Collapsed"))
    }

    /// A sidebar symbol, drawn semibold so that it stands out from its label. The weight is set on the image and
    /// not on the list, because `fontWeight` passes down the environment and would make the labels heavier too.
    private func icon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .fontWeight(.semibold)
    }

    private func row(for tool: Tool) -> some View {
        HStack(spacing: 0) {
            Label {
                Text(tool.title)
            } icon: {
                icon(tool.systemImage)
            }
            if tool == .home {
                Spacer(minLength: 8)
                AttentionBadge()
                    .opacity(home.needsAttention ? 1 : 0)
                    .accessibilityHidden(!home.needsAttention)
                    .motion(value: home.needsAttention)
            }
        }
        .background {
            if tool == .home { ruler }
        }
        .tag(SidebarDestination.tool(tool))
    }

    /// Every label the column can show, laid out in the rows' font but never drawn, to measure the widest one. The
    /// width then follows the language, the text size, Bold Text, and the tools left out. It sits behind the Home
    /// row, which is shown whichever groups are collapsed and whatever is hidden.
    private var ruler: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label { Text(Tool.home.title) } icon: { icon(Tool.home.systemImage) }
                // Stands in for the attention badge that can appear beside Home.
                Color.clear.frame(width: 16, height: 1)
            }
            ForEach(shown(Tool.allCases.filter { $0 != .home })) { tool in
                Label { Text(tool.title) } icon: { icon(tool.systemImage) }
            }
            Label { Text("Settings") } icon: { icon("gearshape") }
            // The head's version line and the room the face and the icon take around it, so the head fits too.
            HStack(spacing: 0) {
                versionLine.font(.caption)
                Color.clear.frame(width: headRoom, height: 1)
            }
            ForEach(Tool.Group.allCases, id: \.self) { group in
                if let title = group.title, !shown(group.tools).isEmpty {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                }
            }
        }
        .fixedSize()
        .hidden()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { widest in
            widestLabel = widest
            fitWidth()
        }
    }

    private var headRoom: CGFloat {
        let icon = library.newerPeel == nil ? 0 : Head.spacing + Head.icon
        return 2 * Head.margin + Head.leading + Head.face + Head.spacing + icon + Head.trailing - Self.rowInsets
    }

    private func fitWidth() {
        width = max(min(ceil(widestLabel) + Self.rowInsets, Self.maximumWidth) + scrollerRoom, Self.minimumWidth)
    }
}

/// The red badge that marks a missing required permission, beside Home in the sidebar and on Home itself.
struct AttentionBadge: View {
    var size: CGFloat = 16
    var fill: Color = .red

    var body: some View {
        RoundedRectangle(cornerRadius: size / 4, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "exclamationmark")
                    .font(.system(size: size * 0.56, weight: .black))
                    .foregroundStyle(.white)
            )
            .accessibilityLabel(Text("Needs your attention"))
    }
}
