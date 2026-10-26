import Foundation
@testable import PeelCore
import Testing

struct IntelPluginHostTests {
    @Test func saysWhereAnIntelPlugInCanStillLoad() {
        #expect(Plugin.Category.audioDrivers.intelHost == .aProcessOfItsOwn)
        #expect(Plugin.Category.screenSavers.intelHost == .aProcessOfItsOwn)
        #expect(Plugin.Category.audioUnits.intelHost == .outsideTheAppWhenAsked)
        #expect(Plugin.Category.vst3.intelHost == .insideTheApp)
        #expect(Plugin.Category.colorPickers.intelHost == .insideTheApp)
        #expect(Plugin.Category.services.intelHost == .notKnown)
    }

    @Test func everyHostMacOSKeepsForIntelPlugInsIsInTheSealedSystem() {
        let ownProcess = Plugin.Category.allCases.filter { $0.intelHost == .aProcessOfItsOwn || $0 == .audioUnits }
        #expect(Set(Plugin.Category.intelHostPrograms.keys) == Set(ownProcess))
        for (category, program) in Plugin.Category.intelHostPrograms {
            let architectures = MachOHeader.architectures(ofExecutableAt: URL(filePath: program))
            #expect(architectures?.contains(.x86_64) == true, "\(category): \(program)")
        }
    }
}
