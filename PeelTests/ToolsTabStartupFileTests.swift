import Foundation
@testable import Peel
import PeelCore
import Testing

struct ToolsTabStartupFileTests {
    /// With ZDOTDIR set, zsh reads another .zshrc, and the Tools tab names the one the Shell tab found.
    @Test func theToolsTabNamesTheFileZshReads() {
        let zshrc = "~/.config/zsh/.zshrc"

        for place in [TerminalTool.Place.zshrc, .lastLineOfZshrc] {
            #expect(String(localized: place.caption(zshrc: zshrc)).contains(zshrc))
        }
        #expect(String(localized: ToolsTab.linesGoIn(zshrc)).contains(zshrc))
        #expect(!TerminalTool.zshSyntaxHighlighting.detail.key.contains("~/.zshrc"))
    }
}
