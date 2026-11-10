import Foundation
import PeelPrivileged

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let lifetime: HelperLifetime
    private let codeSigningRequirement: String

    init(lifetime: HelperLifetime, codeSigningRequirement: String) {
        self.lifetime = lifetime
        self.codeSigningRequirement = codeSigningRequirement
    }

    /// Takes Peel's connection from any account: each request is served only for an administrator, or with an
    /// administrator's approval (`HelperRequest.caller`).
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        lifetime.connectionOpened()

        // The listener checks the code only when it connects; with this, a message from any other code closes the
        // connection (`NSXPCConnection.h`), so a connection handed to another process is never served.
        connection.setCodeSigningRequirement(codeSigningRequirement)
        connection.exportedInterface = HelperOperations.exportedInterface()
        connection.exportedObject = HelperService(lifetime: lifetime)
        connection.invalidationHandler = { [lifetime] in
            lifetime.connectionClosed()
        }
        connection.resume()
        return true
    }
}
