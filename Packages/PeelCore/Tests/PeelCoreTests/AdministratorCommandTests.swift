import Foundation
@testable import PeelCore
import Testing

struct AdministratorCommandTests {
    @Test func aCommandThatUsesSudoNeedsAnAdministratorOnAStandardAccount() {
        #expect(AdministratorCommand.needsAnAdministrator("sudo rm /etc/paths.d/postgresapp", isAdministrator: false))
        #expect(!AdministratorCommand.needsAnAdministrator("sudo rm /etc/paths.d/postgresapp", isAdministrator: true))
        #expect(AdministratorCommand.needsAnAdministrator("mkdir -p a && sudo ln -s b c", isAdministrator: false))
        #expect(!AdministratorCommand.needsAnAdministrator("chmod u+w '/opt/homebrew'", isAdministrator: false))
        #expect(!AdministratorCommand.needsAnAdministrator("echo pseudo-sudo", isAdministrator: false))
    }
}
