@testable import Peel
import Testing

@MainActor
struct CommandLineRowTests {
    @Test func aStandardAccountCannotInstallTheTool() {
        #expect(HomeModel.commandLineState(isOnThePath: true, isAdministrator: false) == .on)
        #expect(HomeModel.commandLineState(isOnThePath: false, isAdministrator: true) == .off)
        #expect(HomeModel.commandLineState(isOnThePath: false, isAdministrator: false) == .notThisAccount)
    }
}
