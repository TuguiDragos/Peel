import Foundation
import PeelPrivileged

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let lifetime: HelperLifetime

    init(lifetime: HelperLifetime) {
        self.lifetime = lifetime
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard UserAuthorization.isAdministrator(connection.effectiveUserIdentifier) else { return false }

        connection.exportedInterface = Self.interface()
        connection.exportedObject = HelperService(lifetime: lifetime)
        lifetime.connectionOpened()
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
