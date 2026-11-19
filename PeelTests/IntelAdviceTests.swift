import Foundation
@testable import Peel
import PeelCore
import Testing

struct IntelAdviceTests {
    private func advice(
        _ kind: IntelFinding.Kind, formula: String? = nil, cask: String? = nil, onPlugIns: Bool = false,
        receipt: Bool = false
    ) -> IntelDetailView.Advice {
        IntelDetailView.advice(
            for: kind, formula: formula, cask: cask, isOnThePlugInsPage: onPlugIns, hasReceipt: receipt
        )
    }

    @Test func eachFindingSaysTheStepWithWhyInItsNote() {
        #expect(advice(.commandLineTool, formula: "x").step.key == "Installed by Homebrew")
        #expect(advice(.commandLineTool, formula: "x").why?.key == "It goes when Homebrew uninstalls the formula %@.")
        #expect(advice(.commandLineTool, cask: "x").why?.key == "It goes when Homebrew uninstalls the cask %@.")
        #expect(advice(.driver).step.key == "Remove it with its software")
        #expect(advice(.app).step.key == "Remove it in Applications")
        #expect(advice(.app).why?.key == "There you see everything that goes with the app.")
        #expect(advice(.insideApp).step.key == "Comes with its app")
        #expect(advice(.plugin, onPlugIns: true).step.key == "Remove it in Plug-ins")
        #expect(advice(.plugin, onPlugIns: true).why == nil)
        #expect(advice(.plugin).step.key == "Remove it with its software")
        #expect(advice(.backgroundItem).why?.key == "Background Items moves only the file of the job, not the program it runs.")
        #expect(advice(.javaRuntime).step.key == "Remove it in Finder")
        #expect(advice(.javaRuntime, receipt: true).step.key == "Remove it in Package Receipts")
        #expect(advice(.javaRuntime, formula: "openjdk").step.key == "Remove it with Homebrew")
    }

    @Test func theOtherSentencesAreShorter() {
        #expect(IntelDetailView.intelBasedAppsList.key == "System Settings > General > About > Intel-based Apps lists the apps macOS 28 will not run. Peel also looks inside apps and at plug-ins and drivers.")
    }
}
