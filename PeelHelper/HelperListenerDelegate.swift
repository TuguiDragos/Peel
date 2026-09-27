import Foundation
import PeelPrivileged

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let lifetime: HelperLifetime
    private let codeSigningRequirement: String

    init(lifetime: HelperLifetime, codeSigningRequirement: String) {
        self.lifetime = lifetime
        self.codeSigningRequirement = codeSigningRequirement
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let isAdministrator = { UserAuthorization.isAdministrator(connection.effectiveUserIdentifier) }
        guard lifetime.accept(isAdministrator) else { return false }

        // The listener checks the code only when it connects; with this, a message from any other code closes the
        // connection (`NSXPCConnection.h`), so a connection handed to another process is never served.
        connection.setCodeSigningRequirement(codeSigningRequirement)
        connection.exportedInterface = Self.interface()
        connection.exportedObject = HelperService(lifetime: lifetime)
        connection.invalidationHandler = { [lifetime] in
            lifetime.connectionClosed()
        }
        connection.resume()
        return true
    }

    /// Builds the interface the helper exports, with every collection in `moveItemsToTrash` limited to
    /// strings. `NSXPCConnection.h` makes this optional for property list types, and here it keeps a client
    /// from sending anything else.
    private static func interface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: (any PeelHelperProtocol).self)
        let trash = #selector((any PeelHelperProtocol).moveItemsToTrash(version:atPaths:withReply:))
        interface.setClasses(classes(NSArray.self, NSString.self), for: trash, argumentIndex: 1, ofReply: false)
        for index in 0...1 {
            interface.setClasses(classes(NSDictionary.self, NSString.self), for: trash, argumentIndex: index, ofReply: true)
        }
        return interface
    }

    private static func classes(_ allowed: AnyClass...) -> Set<AnyHashable> {
        NSSet(array: allowed) as? Set<AnyHashable> ?? []
    }
}
