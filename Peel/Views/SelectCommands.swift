import PeelCore
import SwiftUI

/// A page's Select Recommended, Select All and Deselect All, offered in the Edit menu as well as in its lists' Select
/// menus, so the keyboard reaches them too.
struct SelectCommands {
    let recommended: MenuCommand?
    let all: MenuCommand
    let none: MenuCommand
}

extension View {
    /// Offers the Select commands for every row of the page's lists, `list`, in the Edit menu, with the question
    /// Select All asks first. `place` names the page in that question.
    func selectCommands(
        list: SelectableRows<URL>, place: Text, selection: any RowSelection, removesDownloads: Bool = false
    ) -> some View {
        modifier(SelectCommandsHost(list: list, place: place, selection: selection, removesDownloads: removesDownloads))
    }
}

private struct SelectCommandsHost: ViewModifier {
    let list: SelectableRows<URL>
    let place: Text
    let selection: any RowSelection
    let removesDownloads: Bool
    @State private var notRecommended: Int?

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.selectRows, list.selectable.isEmpty ? nil : commands)
            .selectAllQuestion(
                Text("Select everything in “\(place)”?"), notRecommended: $notRecommended, list: list,
                selection: selection, removesDownloads: removesDownloads
            )
    }

    private var commands: SelectCommands {
        let selected = selection.selectedURLs
        // Where Peel recommends every row a click can select, Select Recommended would only repeat Select All.
        let recommended = list.recommended.count < list.selectable.count ? MenuCommand(
            title: "Select Recommended",
            isEnabled: !list.recommended.isEmpty && !list.isRecommendedSelected(in: selected)
        ) { [selection, list] in
            selection.select(list.selectingRecommended(in: selection.selectedURLs))
        } : nil
        let asks = !list.notRecommendedAdded(by: selected).isEmpty
        let all = MenuCommand(title: asks ? "Select All…" : "Select All", isEnabled: !list.isAllSelected(in: selected)) {
            let added = list.notRecommendedAdded(by: selection.selectedURLs).count
            if added == 0 {
                selection.select(list.selectingAll(in: selection.selectedURLs))
            } else {
                notRecommended = added
            }
        }
        let none = MenuCommand(title: "Deselect All", isEnabled: !list.isNoneSelected(in: selected)) { [selection, list] in
            selection.select(list.deselectingAll(in: selection.selectedURLs))
        }
        return SelectCommands(recommended: recommended, all: all, none: none)
    }
}
