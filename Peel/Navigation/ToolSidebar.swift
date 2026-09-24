import AppKit
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("sidebar.apps.expanded") private var isAppsExpanded = true
    @AppStorage("sidebar.storage.expanded") private var isStorageExpanded = true
    @AppStorage("sidebar.system.expanded") private var isSystemExpanded = true
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
        NSScroller.preferredScrollerStyle == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
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
                ForEach(Tool.Group.home.tools, content: row)
                Label { Text("Settings") } icon: { icon("gearshape") }
                    .tag(SidebarDestination.settings)
            }

            group(.apps, isExpanded: $isAppsExpanded)
            group(.storage, isExpanded: $isStorageExpanded)
            group(.system, isExpanded: $isSystemExpanded)
        }
        .safeAreaBar(edge: .top, spacing: 0) { mascot }
        .takesFocusWhenNothingHasIt()
        .onReceive(NotificationCenter.default.publisher(for: NSScroller.preferredScrollerStyleDidChangeNotification)) { _ in
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
    /// It rises into the lower half of the title bar, which is otherwise empty above the sidebar.
    private var mascot: some View {
        Button {
            page = .about
        } label: {
            HStack(spacing: 9) {
                PeelFace(size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Peel")
                        .font(.callout.weight(.semibold))
                    Text(verbatim: AppVersion.display)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 7)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 10)
        .padding(.top, -8)
        .padding(.bottom, 8)
        .accessibilityLabel(Text(AboutView.title))
        .accessibilityValue(Text(verbatim: AppVersion.display))
    }

    /// A group whose rows are added and removed here rather than by a collapsible `Section`, because SwiftUI
    /// restores a section's expanded state on its own and would decide whether a group starts open.
    @ViewBuilder
    private func group(_ group: Tool.Group, isExpanded: Binding<Bool>) -> some View {
        Section {
            heading(group, isExpanded: isExpanded)
            if isExpanded.wrappedValue {
                rows(in: group)
            }
        }
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

    private func rows(in group: Tool.Group) -> some View {
        ForEach(group.tools) { tool in
            row(for: tool)
        }
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
    /// width then follows the language, the text size, and Bold Text. It sits behind the Home row, which is shown
    /// whichever groups are collapsed.
    private var ruler: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label { Text(Tool.home.title) } icon: { icon(Tool.home.systemImage) }
                // Stands in for the attention badge that can appear beside Home.
                Color.clear.frame(width: 16, height: 1)
            }
            ForEach(Tool.allCases.filter { $0 != .home }) { tool in
                Label { Text(tool.title) } icon: { icon(tool.systemImage) }
            }
            Label { Text("Settings") } icon: { icon("gearshape") }
            ForEach(Tool.Group.allCases, id: \.self) { group in
                if let title = group.title {
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

    private func fitWidth() {
        width = max(min(ceil(widestLabel) + Self.rowInsets, Self.maximumWidth) + scrollerRoom, Self.minimumWidth)
    }
}

/// The red badge that marks a missing required permission, beside Home in the sidebar and on Home itself.
struct AttentionBadge: View {
    var size: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: size / 4, style: .continuous)
            .fill(.red)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "exclamationmark")
                    .font(.system(size: size * 0.56, weight: .black))
                    .foregroundStyle(.white)
            )
            .accessibilityLabel(Text("Needs your attention"))
    }
}
