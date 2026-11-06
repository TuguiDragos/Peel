import SwiftUI

/// Returns the height of a Settings list with `rows` entries, at 24 points a row: the list fits its entries, up to
/// eight rows, and scrolls beyond that.
func settingsListHeight(rows: Int) -> CGFloat {
    CGFloat(min(rows, 8)) * 24
}

extension View {
    /// Styles the buttons beside a Settings row as small bordered buttons, 20 points high, the
    /// HIG's minimum on the Mac. A borderless pull-down stays 16 points high at every control size, so they all use
    /// this style.
    func editingControls() -> some View {
        buttonStyle(.bordered)
            .controlSize(.small)
    }
}

/// The `+` and `-` at the foot of a Settings list, as macOS's own lists have them: symbols at the left, each named by
/// its tooltip and to VoiceOver.
struct ListEditingButtons<Buttons: View>: View {
    @ViewBuilder let buttons: Buttons

    var body: some View {
        HStack(spacing: 4) {
            buttons
            Spacer(minLength: 0)
        }
        .labelStyle(EditingSymbolLabelStyle())
        .editingControls()
    }
}

/// A symbol alone, named by its title for VoiceOver, and as tall as a line of text: a small bordered button is its
/// label's height and six points, so a minus alone would make it 9 points high.
private struct EditingSymbolLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration)
            .labelStyle(.iconOnly)
            .frame(minHeight: 14)
    }
}
